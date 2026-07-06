# HPL x86 Benchmark Suite

Clean, modular benchmarking scripts for evaluating HPL performance under varying **ondemand CPU governor** parameters.

Supports both **single-configuration runs** and **automated sweeps** across sampling_rate and threshold parameter grids.

---

## Features

- **Flexible execution modes**:
  - Single run: `./run_ondemand_new.sh --sampling-rate 10000 --threshold 95`
  - Automated sweep: `./run_threshold_sweep.sh --thresholds "75,80,85,90,95"`

- **Comprehensive metrics collection**:
  - CPU frequency (target core + all cores)
  - CPU utilization (target core + all cores)
  - Voltage (per-core, averaged)
  - Power consumption (system via powerstat)
  - HPL performance (GFLOPS)
  - Response time per HPL run (MRT)

- **Structured output archiving**:
  - Results organized by date and configuration:
    ```
    Dataset/x86_benchmark/20260420/sr/10000/threshold/95/nohup.log
                                     ↑                    ↑
                                sampling_rate       threshold
    ```
  - All logs per configuration collected immediately after run completes

- **Clean, commented code** with proper error handling

---

## Prerequisites

- **HPL binary**: `bin/Linux/xhpl` (relative to repo root)
- **HPL configuration**: `HPL.dat` (relative to repo root)
- **System tools**: `mpstat`, `powerstat`, `bc`, `awk`, `cpupower`, `rdmsr`
- **Privileges**: `sudo` access required for CPU frequency and power measurement

On Ubuntu/Debian:
```bash
sudo apt-get install sysstat -y  # for mpstat
sudo apt-get install linux-tools-generic -y  # for powerstat
sudo apt-get install intel-msr-tools -y  # for rdmsr (if available)
```

---

## Usage

### Single Configuration Run

Execute HPL with fixed ondemand governor parameters:

```bash
./run_ondemand_new.sh \
  --sampling-rate 10000 \
  --threshold 95
```

**Optional parameters**:
- `--core N` – Target CPU core (default: 3)
- `--runs N` – Number of HPL benchmark repetitions (default: 1)
- `--min-freq HZ` – Minimum CPU frequency in Hz (default: 800000)
- `--max-freq HZ` – Maximum CPU frequency in Hz (default: 2100000)
- `--duration-sec S` – Total benchmark duration in seconds (default: 600)

**Example: Low-frequency baseline**:
```bash
./run_ondemand_new.sh \
  --core 3 \
  --runs 3 \
  --min-freq 800000 \
  --max-freq 1600000 \
  --sampling-rate 50000 \
  --threshold 80 \
  --duration-sec 300
```

### Full Sweep Across Parameters

Benchmark all combinations of sampling_rate and threshold:

```bash
./run_threshold_sweep.sh \
  --sampling-rates "10000,30000,50000,100000" \
  --thresholds "75,85,95"
```

This executes `4 × 3 = 12` configurations sequentially.

**Optional parameters**:
- `--core N`, `--runs N`, `--min-freq`, `--max-freq`, `--duration-sec` – same as single-run script
- `--sampling-rates "SR1,SR2,..."` – Comma-separated sampling rates (μs)
- `--thresholds "TH1,TH2,..."` – Comma-separated thresholds (%)

**Example: Quick sweep**:
```bash
./run_threshold_sweep.sh \
  --sampling-rates "10000,100000" \
  --thresholds "75,95" \
  --duration-sec 120 \
  --runs 2
```

---

## Output Structure

Results are organized deterministically:

```
Dataset/x86_benchmark/
├── 20260420/                     # Benchmark date (YYYYMMDD)
│   └── sr/
│       ├── 10000/                # Sampling rate (microseconds)
│       │   └── threshold/
│       │       ├── 75/
│       │       │   └── nohup.log           # Run log + results
│       │       │   ├── core_freq_*.log
│       │       │   ├── cpu_cores_freq_*.log
│       │       │   ├── core_utilization_*.log
│       │       │   ├── cpu_utilization_*.log
│       │       │   ├── cpu_power_*.log
│       │       │   ├── cpu_cores_voltage_*.log
│       │       │   ├── hpl_*.out
│       │       │   └── mrt_times_*.log
│       │       ├── 80/
│       │       │   └── [same logs]
│       │       └── 95/
│       │           └── [same logs]
│       └── 20000/
│           └── threshold/
│               └── [same structure]
```

Each configuration gets its own directory. The `nohup.log` contains:
- Run configuration (core, freq range, SR, TH)
- Per-run progress messages
- Metrics summary (frequency, voltage, utilization, power, GFLOPS)
- Archival confirmation

---

## Log Files Explained

Per-run metrics collected in each config directory:

| File | Contents |
|------|----------|
| `nohup.log` | Merged stdout/stderr with all progress and results |
| `core_freq_SR_TH_N.log` | Target core frequency samples (timestamp, Hz) |
| `cpu_cores_freq_SR_TH_N.log` | All cores' frequencies (timestamp, Hz₀, Hz₁, ...) |
| `core_utilization_SR_TH_N.log` | Target core CPU utilization (mpstat output) |
| `cpu_utilization_SR_TH_N.log` | All cores' utilization (mpstat output) |
| `cpu_power_SR_TH_N.log` | Power samples from powerstat (watts) |
| `cpu_cores_voltage_SR_TH_N.log` | Per-core voltages via MSR (timestamp, V₀, V₁, ..., avg_V) |
| `hpl_SR_TH_N.out` | HPL binary stdout/stderr |
| `mrt_times_SR_TH_N.log` | Individual HPL run times (milliseconds per run) |

Where `SR` = sampling_rate, `TH` = threshold, `N` = run number.

---

## Helper Functions

**`helpers.sh`** – Power modeling (reused from repo root):
- `read_cpu_voltage_msr(core)` – Read per-core voltage via Intel MSR 0x198
- `interpolate_cpu_idle_power(freq_hz)` – Piecewise-linear idle power model
- `compute_cpu_p_dynamic(freq_khz, voltage)` – Dynamic power: P = Ceff × V² × f
- `modeled_power(freq, voltage, util, num_cores)` – Estimated core power

**`lib/common.sh`** – Utilities:
- `safe_kill(pid)` – Force-kill with existence check
- `safe_wait(pid)` – Wait on PID, ignore "already gone" errors
- `require_commands(...)` – Fail fast if tools missing
- `ensure_output_dir(SR, TH, date)` – Create and return canonical path
- `archive_configuration_logs(core, SR, TH, dest)` – Move all logs to result directory
- `archive_pattern_if_exists(pattern, dest)` – Glob-based archival

---

## Error Handling

Scripts use `set -euo pipefail` and include:
- Early validation of HPL binary, configuration files, required system tools
- Graceful cleanup of background sampler processes on exit or interruption
- Per-configuration error logging (continues sweep even if one config fails)
- Trap handlers (`cleanup`) to kill stray processes on Ctrl+C

---

## Customization

### Change default parameters

Export environment variables before running:
```bash
export CORE=5
export MIN_FREQ=1000000
export DURATION_SEC=300
./run_ondemand_new.sh --sampling-rate 10000 --threshold 95
```

### Use custom HPL configuration

Place `HPL.dat` in the repo root or adjust `HPL_BINARY`/`HPL_DATA` in `run_ondemand_new.sh`.

### Modify data storage path

Edit `DATA_ROOT` in `lib/common.sh`:
```bash
DATA_ROOT="/custom/path/x86_benchmark"
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `HPL binary not found` | Ensure `bin/Linux/xhpl` is built and executable |
| `HPL.dat not found` | Place `HPL.dat` in repo root |
| `Missing required command` | Install sysstat, linux-tools, intel-msr-tools |
| `Permission denied` on /sys | Scripts require `sudo` for frequency/power access |
| `rdmsr` not available | Voltage sampling will return "N/A"; power estimates still computed |
| Logs not archived | Check `archive_configuration_logs()` output in nohup.log |

---

## Performance Notes

- **Benchmark duration**: Default 600s (10 min) per configuration
- **Sampler overhead**: ~0.2% CPU per frequency/voltage sampler
- **Disk storage**: ~10 MB per configuration (depends on sampling interval)
- **Full sweep of 10×5=50 configs**: ~8.5 hours at 600s/config (add rest time + overhead)

---

## License & Attribution

Benchmarking suite for HPL. Based on x86 processor power modeling and Intel MSR voltage sampling.
