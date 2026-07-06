#!/bin/bash

set -euo pipefail

# ============================================================================
# HPL x86 Benchmark: Single Ondemand Governor Configuration Run
#
# Executes HPL with a fixed (sampling_rate, threshold) ondemand configuration.
# Collects CPU frequency, utilization, voltage, and power metrics throughout.
# Automatically archives all logs to a dated/structured directory.
# ============================================================================

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
RUNNER_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
ROOT_DIR="${HPL_ROOT:-$(cd "$RUNNER_DIR/.." && pwd)}"

# Source helper functions
source "$RUNNER_DIR/helpers.sh"
source "$RUNNER_DIR/lib/common.sh"

# ============================================================================
# Configuration Defaults (overridable via environment or CLI args)
# ============================================================================

CORE="${CORE:-3}"                              # Target CPU core
RUNS="${RUNS:-1}"                              # Repetitions per configuration
MIN_FREQ="${MIN_FREQ:-800000}"                 # Minimum CPU frequency (Hz)
MAX_FREQ="${MAX_FREQ:-2100000}"                # Maximum CPU frequency (Hz)
SAMPLING_RATE="${SAMPLING_RATE:-10000}"        # Ondemand sampling_rate (μs)
THRESHOLD="${THRESHOLD:-95}"                   # Ondemand up_threshold (%)
UTILIZATION="${UTILIZATION:-100}"              # HPL dataset utilization load (%): 10..100
NUM_CPUS="${NUM_CPUS:-$(( $(nproc) + 2 ))}"   # Total logical cores
CORE_IDLE_POWER="${CORE_IDLE_POWER:-0.58}"    # Baseline core idle power (W)
GOVERNOR="ondemand"
POWERSTAT_INTERVAL="${POWERSTAT_INTERVAL:-1}"  # Power measurement interval (s)
DURATION_SEC="${DURATION_SEC:-600}"            # Total benchmark duration (10 min)
SLEEP_BETWEEN_RUNS="${SLEEP_BETWEEN_RUNS:-10}" # Rest period between runs (s)
BENCHMARK_DATE="${BENCHMARK_DATE:-$(date +%Y%m%d)}" # Date tag for result paths
DATASET_DIR="${DATASET_DIR:-$ROOT_DIR/data_set/hpl_utilization}"

# ============================================================================
# CLI Argument Parsing
# ============================================================================

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Execute HPL benchmark with fixed ondemand governor configuration.
Collects frequency, utilization, voltage, and power metrics.

Options:
  --core N                 Target core number (default: $CORE)
  --runs N                 Benchmark repetitions (default: $RUNS)
  --min-freq HZ            Minimum frequency in Hz (default: $MIN_FREQ)
  --max-freq HZ            Maximum frequency in Hz (default: $MAX_FREQ)
  --sampling-rate US       Ondemand sampling_rate in microseconds (default: $SAMPLING_RATE)
  --threshold PERCENT      Ondemand up_threshold in percent (default: $THRESHOLD)
  --utilization PERCENT    HPL utilization dataset to load (default: $UTILIZATION)
  --num-cpus N             Total logical CPU cores (default: $NUM_CPUS)
  --duration-sec S         Total benchmark duration in seconds (default: $DURATION_SEC)
  --help                   Show this help message and exit

EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --core) CORE="$2"; shift 2 ;;
    --runs) RUNS="$2"; shift 2 ;;
    --min-freq) MIN_FREQ="$2"; shift 2 ;;
    --max-freq) MAX_FREQ="$2"; shift 2 ;;
    --sampling-rate) SAMPLING_RATE="$2"; shift 2 ;;
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --utilization) UTILIZATION="$2"; shift 2 ;;
    --num-cpus) NUM_CPUS="$2"; shift 2 ;;
    --duration-sec) DURATION_SEC="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *)
      echo "[ERROR] Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# ============================================================================
# Pre-flight Checks
# ============================================================================

require_commands bc awk mpstat taskset sudo cpupower powerstat || exit 1

HPL_BINARY="$ROOT_DIR/bin/Linux/xhpl"
if [[ ! -x "$HPL_BINARY" ]]; then
  echo "[ERROR] HPL binary not found or not executable: $HPL_BINARY" >&2
  exit 1
fi

if [[ ! "$UTILIZATION" =~ ^(10|20|30|40|50|60|70|80|90|100)$ ]]; then
  echo "[ERROR] utilization must be one of: 10,20,30,40,50,60,70,80,90,100" >&2
  exit 1
fi

if [[ ! -d "$DATASET_DIR" ]]; then
  ALT_DATASET_DIR_1="$ROOT_DIR/data_set"
  ALT_DATASET_DIR_2="$RUNNER_DIR/data_set"
  if [[ -d "$ALT_DATASET_DIR_1" ]]; then
    DATASET_DIR="$ALT_DATASET_DIR_1"
  elif [[ -d "$ALT_DATASET_DIR_2" ]]; then
    DATASET_DIR="$ALT_DATASET_DIR_2"
  else
    echo "[ERROR] dataset directory not found: $DATASET_DIR (or $ALT_DATASET_DIR_1 or $ALT_DATASET_DIR_2)" >&2
    exit 1
  fi
fi

DATASET_FILE="$DATASET_DIR/HPL_${UTILIZATION}.dat"
if [[ ! -f "$DATASET_FILE" ]]; then
  echo "[ERROR] dataset file not found: $DATASET_FILE" >&2
  exit 1
fi

install_dataset_for_utilization() {
  local util="$1"
  local source_file="$2"
  local target_file="$ROOT_DIR/HPL.dat"

  echo "[INFO] Installing utilization dataset: HPL_${util}.dat"
  echo "[INFO] Source: $source_file"
  echo "[INFO] Target: $target_file"

  sudo cp "$source_file" "$target_file"
  if ! sudo cmp -s "$source_file" "$target_file"; then
    echo "[ERROR] HPL.dat copy verification failed for utilization=$util" >&2
    exit 1
  fi
}

# ============================================================================
# Output Directory Setup & Logging
# ============================================================================

OUTPUT_DIR="$(ensure_output_dir "$SAMPLING_RATE" "$THRESHOLD" "$BENCHMARK_DATE")"
RESULTS_DIR="$ROOT_DIR/Dataset/x86_benchmark/$BENCHMARK_DATE"
mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/hpl_results.csv"
RUN_LOG="$OUTPUT_DIR/nohup.log"

# Tee all output to both stdout and the persistent run log
exec > >(tee -a "$RUN_LOG") 2>&1

echo "[INFO] =========================================="
echo "[INFO] HPL x86 Benchmark Configuration Run"
echo "[INFO] =========================================="
echo "[INFO] Output directory: $OUTPUT_DIR"
echo "[INFO] Core: $CORE | Min freq: $MIN_FREQ Hz | Max freq: $MAX_FREQ Hz"
echo "[INFO] Sampling rate: ${SAMPLING_RATE} μs | Threshold: ${THRESHOLD}%"
echo "[INFO] Utilization dataset: HPL_${UTILIZATION}.dat"
echo "[INFO] Duration: ${DURATION_SEC}s | Repetitions: $RUNS"

# Run from repository root so xhpl can always open HPL.dat.
cd "$ROOT_DIR"
install_dataset_for_utilization "$UTILIZATION" "$DATASET_FILE"

# ============================================================================
# Cleanup Handler & PID Tracking
# ============================================================================

cleanup_pids=()
cleanup() {
  echo "[INFO] Cleaning up background processes..."
  for pid in "${cleanup_pids[@]:-}"; do
    safe_kill "$pid"
  done
}
trap cleanup EXIT

# ============================================================================
# CPU Governor & Frequency Configuration
# ============================================================================

echo "[INFO] Preparing CPU governor state"

# Set intel_pstate to passive mode to allow manual cpufreq control
echo passive | sudo tee /sys/devices/system/cpu/intel_pstate/status >/dev/null 2>&1 || true

# Set all cores to userspace governor at minimum frequency (baseline)
sudo cpupower -c all frequency-set -g userspace >/dev/null 2>&1 || true
sudo cpupower -c all frequency-set -d "$MIN_FREQ" -u "$MIN_FREQ" >/dev/null 2>&1 || true

# Configure target core: ondemand governor with frequency bounds
echo "[INFO] Configuring core $CORE: governor=$GOVERNOR freq=$MIN_FREQ-$MAX_FREQ Hz"
sudo cpupower -c "$CORE" frequency-set -g "$GOVERNOR" -d "$MIN_FREQ" -u "$MAX_FREQ" >/dev/null 2>&1

# ============================================================================
# Benchmark Loop: Execute HPL Runs
# ============================================================================

RUN_COUNT=0
START_TIME=$(date +%s.%N)
TOTAL_HPL_RUNS=0

while [[ $RUN_COUNT -lt $RUNS ]]; do
  RUN_COUNT=$((RUN_COUNT + 1))
  CURRENT_ELAPSED=$(($(date +%s) - ${START_TIME%.*}))

  echo ""
  echo "[INFO] Run $RUN_COUNT/$RUNS | Elapsed: ${CURRENT_ELAPSED}s / ${DURATION_SEC}s"

  # Apply ondemand control knobs for this run
  echo "$SAMPLING_RATE" | sudo tee /sys/devices/system/cpu/cpufreq/ondemand/sampling_rate >/dev/null 2>&1
  echo "$THRESHOLD" | sudo tee /sys/devices/system/cpu/cpufreq/ondemand/up_threshold >/dev/null 2>&1

  # Log file names: metric_utilization_sampling_rate_threshold_iteration.log
  cpu_power_log="cpu_power_${UTILIZATION}_${SAMPLING_RATE}_${THRESHOLD}_${RUN_COUNT}.log"
  core_freq_log="core_freq_${UTILIZATION}_${SAMPLING_RATE}_${THRESHOLD}_${RUN_COUNT}.log"
  cpu_cores_freq_log="cpu_cores_freq_${UTILIZATION}_${SAMPLING_RATE}_${THRESHOLD}_${RUN_COUNT}.log"
  core_util_log="core_utilization_${UTILIZATION}_${SAMPLING_RATE}_${THRESHOLD}_${RUN_COUNT}.log"
  cpu_util_log="cpu_utilization_${UTILIZATION}_${SAMPLING_RATE}_${THRESHOLD}_${RUN_COUNT}.log"
  cpu_cores_volt_log="cpu_cores_voltage_${UTILIZATION}_${SAMPLING_RATE}_${THRESHOLD}_${RUN_COUNT}.log"
  hpl_out_log="hpl_${UTILIZATION}_${SAMPLING_RATE}_${THRESHOLD}_${RUN_COUNT}.out"
  mrt_log="mrt_times_${UTILIZATION}_${SAMPLING_RATE}_${THRESHOLD}_${RUN_COUNT}.log"

  # ========== Kill Stale Processes ==========
  pkill -9 xhpl 2>/dev/null || true
  pkill -9 mpstat 2>/dev/null || true
  sudo pkill -9 powerstat 2>/dev/null || true

  # ========== Power Monitoring (powerstat) ==========
  echo "[INFO] Starting power profiler..."
  sudo powerstat -R "$POWERSTAT_INTERVAL" > "$cpu_power_log" 2>&1 &
  POWERSTAT_PID=$!
  cleanup_pids+=("$POWERSTAT_PID")

  # ========== High-Rate Frequency Sampling ==========
  echo "[INFO] Starting frequency sampler..."
  (
    while true; do
      # Sample target core frequency
      echo "$(date +%s%N), $(cat /sys/devices/system/cpu/cpu${CORE}/cpufreq/scaling_cur_freq)" >> "$core_freq_log"
      # Sample all cores frequencies
      freqs="$(date +%s%N)"
      for cpu in $(seq 0 $((NUM_CPUS - 1))); do
        freq=$(cat /sys/devices/system/cpu/cpu$cpu/cpufreq/scaling_cur_freq 2>/dev/null || echo "0")
        freqs="${freqs},${freq}"
      done
      echo "$freqs" >> "$cpu_cores_freq_log"
      sleep 0.1
    done
  ) &
  FREQ_SAMPLER_PID=$!
  cleanup_pids+=("$FREQ_SAMPLER_PID")

  # ========== Utilization Monitoring ==========
  echo "[INFO] Sampling CPU utilization..."
  mpstat -P ALL 1 > "$cpu_util_log" 2>&1 &
  MPSTAT_ALL_PID=$!
  cleanup_pids+=("$MPSTAT_ALL_PID")

  mpstat -P "$CORE" 1 > "$core_util_log" 2>&1 &
  MPSTAT_CORE_PID=$!
  cleanup_pids+=("$MPSTAT_CORE_PID")

  # ========== High-Rate Voltage Sampling ==========
  echo "[INFO] Starting voltage sampler..."
  (
    while true; do
      timestamp=$(date +%s.%N)
      line="$timestamp"
      voltage_sum=0
      voltage_count=0

      for cpu in $(seq 0 $((NUM_CPUS - 1))); do
        voltage=$(read_cpu_voltage_msr "$cpu")
        if [[ "$voltage" =~ ^\. ]]; then
          voltage="0$voltage"
        fi
        line="${line},${voltage}"
        if [[ "$voltage" != "N/A" ]] && [[ "$voltage" =~ ^[0-9]*\.?[0-9]+$ ]]; then
          voltage_sum=$(echo "$voltage_sum + $voltage" | bc)
          voltage_count=$((voltage_count + 1))
        fi
      done

      avg_voltage="N/A"
      if [[ $voltage_count -gt 0 ]]; then
        avg_voltage=$(echo "scale=3; $voltage_sum / $voltage_count" | bc)
      fi

      echo "${line},${avg_voltage}" >> "$cpu_cores_volt_log"
      sleep 0.1
    done
  ) &
  VOLT_SAMPLER_PID=$!
  cleanup_pids+=("$VOLT_SAMPLER_PID")

  # ========== HPL Workload Execution ==========
  echo "[INFO] Launching HPL benchmark..."
  RUN_WINDOW_START=$(date +%s.%N)
  HPL_INNER_RUNS=0
  while true; do
    RUN_START=$(date +%s%3N)
    taskset -c "$CORE" "$HPL_BINARY" >> "$hpl_out_log" 2>&1
    RUN_END=$(date +%s%3N)
    RUN_TIME=$((RUN_END - RUN_START))
    echo "$RUN_TIME" >> "$mrt_log"
    HPL_INNER_RUNS=$((HPL_INNER_RUNS + 1))

    NOW=$(date +%s.%N)
    WINDOW_ELAPSED=$(echo "$NOW - $RUN_WINDOW_START" | bc -l)
    if (( $(echo "$WINDOW_ELAPSED >= $DURATION_SEC" | bc -l) )); then
      break
    fi
  done
  TOTAL_HPL_RUNS=$((TOTAL_HPL_RUNS + HPL_INNER_RUNS))
  echo "[INFO] HPL completed with $HPL_INNER_RUNS inner runs"

  # Stop all monitors immediately when HPL loop finishes.
  safe_kill "$POWERSTAT_PID"
  safe_kill "$FREQ_SAMPLER_PID"
  safe_kill "$MPSTAT_ALL_PID"
  safe_kill "$MPSTAT_CORE_PID"
  safe_kill "$VOLT_SAMPLER_PID"

  safe_wait "$POWERSTAT_PID"
  safe_wait "$FREQ_SAMPLER_PID"
  safe_wait "$MPSTAT_ALL_PID"
  safe_wait "$MPSTAT_CORE_PID"
  safe_wait "$VOLT_SAMPLER_PID"

  echo "[INFO] Metrics collection complete for run $RUN_COUNT"

  # Check elapsed time; stop if we've exceeded the target duration
  CURRENT_TIME=$(date +%s.%N)
  ELAPSED=$(echo "$CURRENT_TIME - $START_TIME" | bc -l)
  if (( $(echo "$ELAPSED >= $DURATION_SEC" | bc -l) )); then
    echo "[INFO] Target duration reached ($DURATION_SEC s); stopping benchmark"
    break
  fi

  # Rest between runs
  if [[ $RUN_COUNT -lt $RUNS ]]; then
    echo "[INFO] Sleeping ${SLEEP_BETWEEN_RUNS}s before next run"
    sleep "$SLEEP_BETWEEN_RUNS"
  fi
done

END_TIME=$(date +%s.%N)
TOTAL_EXEC_TIME=$(echo "$END_TIME - $START_TIME" | bc -l)

# ============================================================================
# Metrics Post-Processing & Results
# ============================================================================

echo ""
echo "[INFO] =========================================="
echo "[INFO] Post-processing metrics"
echo "[INFO] =========================================="

# Extract average power from powerstat log
read power_count power_energy_sum <<< "$(awk '/^[0-9]{2}:[0-9]{2}:[0-9]{2}/ {sum += $NF; count++} END {print count+0, sum+0}' "$cpu_power_log")"
if [[ "$power_count" -eq 0 ]]; then
  power_count=1  # Avoid division by zero
fi

power_avg_cpu=$(echo "$power_energy_sum / $power_count" | bc -l)
power_avg_core=$(echo "$power_avg_cpu - 11 * $CORE_IDLE_POWER" | bc -l)

# Extract average frequency in KHz
avg_core_freq_khz=$(awk '{sum+=$2; count++} END {if (count > 0) printf "%.2f", sum/count; else print "0.00"}' "$core_freq_log" 2>/dev/null || echo "0.00")
avg_core_freq_mhz=$(echo "scale=2; $avg_core_freq_khz / 1000" | bc -l)

# Extract average voltage for target core
core_voltage_col=$((CORE + 2))
avg_core_voltage=$(awk -F',' -v col="$core_voltage_col" '{total+=$col; count++} END {if (count > 0) print total/count; else print 0}' "$cpu_cores_volt_log" 2>/dev/null || echo "0")

# Extract average core utilization as (100 - avg idle)
avg_core_util=$(awk '/Average:/ && $2 ~ /^[0-9]+$/ {idle=$NF; if (idle ~ /^[0-9.]+$/) {printf "%.2f", 100-idle; found=1; exit}} END {if (!found) print "0.00"}' "$core_util_log" 2>/dev/null || echo "0.00")

# Extract HPL performance (GFLOPs from final iteration)
hpl_gflops=$(grep -E "WR[0-9]+" "$hpl_out_log" 2>/dev/null | awk '{print $(NF-1)}' | tail -1 || echo "0.00")

# Extract MRT (Mean Response Time)
mrt_mean=$(awk '{sum+=$1; count++} END {if(count>0) printf "%.2f", sum/count; else print "0"}' "$mrt_log" 2>/dev/null || echo "0.00")

# Compute modeled power
avg_core_modeled_power=$(modeled_power "$avg_core_freq_khz" "$avg_core_voltage" "$avg_core_util" "$NUM_CPUS")

# Save one CSV row using the legacy benchmark column schema.
if [[ ! -f "$RESULTS_FILE" ]]; then
  echo "CPU Utilization [%],Sampling Rate [µs],Threshold [%],Measured MRT [ms],Measured Mean CORE Frequency [KHz],Measured Mean CORE Voltage [V],Measured Utilization [%],Modeled CORE Power [W],Measured CORE Power [W]" > "$RESULTS_FILE"
fi

echo "$UTILIZATION,$SAMPLING_RATE,$THRESHOLD,${mrt_mean},${avg_core_freq_khz},${avg_core_voltage},${avg_core_util},${avg_core_modeled_power},${power_avg_core}" >> "$RESULTS_FILE"

# ============================================================================
# Results Summary & Archiving
# ============================================================================

echo "[INFO] =========================================="
echo "[INFO] Benchmark Results Summary"
echo "[INFO] =========================================="
echo "[INFO] Total execution time: ${TOTAL_EXEC_TIME}s"
echo "[INFO] Number of HPL runs: $RUN_COUNT"
echo "[INFO] Mean HPL run time (MRT): ${mrt_mean}ms"
echo "[INFO] Average CPU power: ${power_avg_cpu}W"
echo "[INFO] Total CPU energy: ${power_energy_sum}J"
echo "[INFO] Estimated core power: ${power_avg_core}W"
echo "[INFO] Average core frequency: ${avg_core_freq_mhz}MHz (${avg_core_freq_khz}KHz)"
echo "[INFO] Average core voltage: ${avg_core_voltage}V"
echo "[INFO] Average core utilization: ${avg_core_util}%"
echo "[INFO] Modeled core power: ${avg_core_modeled_power}W"
echo "[INFO] HPL performance: ${hpl_gflops} GFLOPS"

echo ""
echo "[INFO] Archiving logs to: $OUTPUT_DIR"
archive_configuration_logs "$CORE" "$SAMPLING_RATE" "$THRESHOLD" "$OUTPUT_DIR"

echo ""
echo "[INFO] =========================================="
echo "[INFO] Benchmark completed successfully"
echo "[INFO] Results stored in: $OUTPUT_DIR"
echo "[INFO] Run log: $RUN_LOG"
echo "[INFO] Results CSV: $RESULTS_FILE"
echo "[INFO] =========================================="
