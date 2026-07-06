#!/bin/bash

set -euo pipefail

# ============================================================================
# HPL x86 Benchmark: Full Parameter Sweep Coordinator
#
# Orchestrates a complete sweep across multiple sampling_rate and threshold
# configurations, invoking run_ondemand_new.sh for each (sr, th) pair.
# ============================================================================

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$SCRIPT_DIR/run_ondemand_new.sh"
BENCHMARK_DATE="${BENCHMARK_DATE:-$(date +%Y%m%d)}"
DATA_ROOT="$ROOT_DIR/Dataset/x86_benchmark"
RESULTS_FINAL_DIR="$DATA_ROOT/$BENCHMARK_DATE"
RESULTS_FINAL_FILE="$RESULTS_FINAL_DIR/hpl_results.csv"

# ============================================================================
# Configuration Defaults
# ============================================================================

CORE="${CORE:-3}"
RUNS="${RUNS:-1}"
MIN_FREQ="${MIN_FREQ:-800000}"
MAX_FREQ="${MAX_FREQ:-2100000}"
DURATION_SEC="${DURATION_SEC:-600}"

# Default parameter grids
UTILIZATIONS=(10 20 30 40 50 60 70 80 90 100)
SAMPLING_RATES=(10000 20000 30000 40000 50000 60000 70000 80000 90000 100000)
THRESHOLDS=(75 80 85 90 95)

# ============================================================================
# CLI Argument Parsing
# ============================================================================

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Sweep across multiple sampling_rate and threshold configurations.
Calls run_ondemand_new.sh for each (sampling_rate, threshold) pair.

Options:
  --core N
    Target core number (default: $CORE)
  
  --runs N
    Benchmark repetitions per configuration (default: $RUNS)
  
  --min-freq HZ
    Minimum CPU frequency in Hz (default: $MIN_FREQ)
  
  --max-freq HZ
    Maximum CPU frequency in Hz (default: $MAX_FREQ)
  
  --duration-sec S
    Benchmark duration in seconds (default: $DURATION_SEC)

  --utilizations "10,20,..."
    Comma-separated list of utilization dataset levels.
    Default: 10,20,30,40,50,60,70,80,90,100
  
  --sampling-rates "10000,20000,..."
    Comma-separated list of sampling rates in microseconds.
    Default: 10000,20000,...,100000
  
  --thresholds "75,80,..."
    Comma-separated list of up_threshold percentages.
    Default: 75,80,85,90,95
  
  --help
    Show this help message and exit

Example:
  $(basename "$0") \\
    --sampling-rates "10000,50000,100000" \\
    --thresholds "75,95" \\
    --duration-sec 300

EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --core) CORE="$2"; shift 2 ;;
    --runs) RUNS="$2"; shift 2 ;;
    --min-freq) MIN_FREQ="$2"; shift 2 ;;
    --max-freq) MAX_FREQ="$2"; shift 2 ;;
    --duration-sec) DURATION_SEC="$2"; shift 2 ;;
    --utilizations)
      IFS=',' read -r -a UTILIZATIONS <<< "$2"
      shift 2
      ;;
    --sampling-rates)
      IFS=',' read -r -a SAMPLING_RATES <<< "$2"
      shift 2
      ;;
    --thresholds)
      IFS=',' read -r -a THRESHOLDS <<< "$2"
      shift 2
      ;;
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

if [[ ! -x "$RUNNER" ]]; then
  echo "[ERROR] Runner script not found or not executable: $RUNNER" >&2
  exit 1
fi

# ============================================================================
# Sweep Execution
# ============================================================================

echo "=========================================="
echo "HPL x86 Benchmark: Parameter Sweep"
echo "=========================================="
echo "[INFO] Core: $CORE"
echo "[INFO] Runs per config: $RUNS"
echo "[INFO] Min freq: $MIN_FREQ Hz | Max freq: $MAX_FREQ Hz"
echo "[INFO] Duration: ${DURATION_SEC}s"
echo "[INFO] Utilizations: ${UTILIZATIONS[*]}"
echo "[INFO] Sampling rates: ${SAMPLING_RATES[*]}"
echo "[INFO] Thresholds: ${THRESHOLDS[*]}"
echo "[INFO] Results CSV will be finalized at: $RESULTS_FINAL_FILE"
echo "=========================================="
echo ""

CONFIG_COUNT=0
TOTAL_CONFIGS=$((${#UTILIZATIONS[@]} * ${#SAMPLING_RATES[@]} * ${#THRESHOLDS[@]}))

# Full factorial sweep across sampling_rate × threshold × utilization
for sampling_rate in "${SAMPLING_RATES[@]}"; do
  for threshold in "${THRESHOLDS[@]}"; do
    for utilization in "${UTILIZATIONS[@]}"; do
      CONFIG_COUNT=$((CONFIG_COUNT + 1))
      echo "[SWEEP] Configuration $CONFIG_COUNT/$TOTAL_CONFIGS"
      echo "[SWEEP] utilization=$utilization sampling_rate=$sampling_rate threshold=$threshold"
      echo ""

      # Invoke single-run benchmark with current configuration
      "$RUNNER" \
        --core "$CORE" \
        --runs "$RUNS" \
        --min-freq "$MIN_FREQ" \
        --max-freq "$MAX_FREQ" \
        --utilization "$utilization" \
        --sampling-rate "$sampling_rate" \
        --threshold "$threshold" \
        --duration-sec "$DURATION_SEC" \
        || {
          echo "[ERROR] Benchmark failed for utilization=$utilization sampling_rate=$sampling_rate threshold=$threshold" >&2
          # Continue to next config rather than aborting entire sweep
        }

      echo ""
      echo "[SWEEP] Finished utilization=$utilization sampling_rate=$sampling_rate threshold=$threshold"
      echo "-------------------------------------------"
      echo ""
    done
  done
done

if [[ -f "$RESULTS_FINAL_FILE" ]]; then
  echo "[INFO] Final results CSV: $RESULTS_FINAL_FILE"
  wc -l < "$RESULTS_FINAL_FILE" | xargs -I{} echo "[INFO] Total data rows across all configs: {}"
else
  echo "[WARN] No results CSV generated" >&2
fi

echo "=========================================="
echo "Sweep completed"
echo "=========================================="
echo "[INFO] All $TOTAL_CONFIGS configurations executed"
