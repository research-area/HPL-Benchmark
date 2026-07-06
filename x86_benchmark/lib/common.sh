#!/bin/bash

set -euo pipefail

# ============================================================================
# HPL x86 Benchmark Common Utilities
# Shared functions for directory layout, process cleanup, validation, and archiving.
# ============================================================================

# Canonical directory references for consistent path resolution.
BENCHMARK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_DIR="$BENCHMARK_DIR/.."
DATA_ROOT="$ROOT_DIR/Dataset/x86_benchmark"

# ============================================================================
# Process Management
# ============================================================================

# Gracefully terminate a PID and fall back to force-kill if still alive.
# Uses SIGTERM first (allows mpstat to print its Average line), then SIGKILL.
safe_kill() {
  local pid="${1:-}"
  if [[ -z "$pid" ]] || [[ ! "$pid" =~ ^[0-9]+$ ]]; then
    return
  fi
  if kill -0 "$pid" 2>/dev/null; then
    kill -15 "$pid" 2>/dev/null || true
    sleep 1
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
  fi
}

# Safe wait wrapper: blocks until PID exits, ignoring "already finished" errors.
# Useful for cleanup handlers that may try to wait on processes already exited.
safe_wait() {
  local pid="${1:-}"
  if [[ -n "$pid" ]] && [[ "$pid" =~ ^[0-9]+$ ]]; then
    wait "$pid" 2>/dev/null || true
  fi
}

# ============================================================================
# Validation & Requirements
# ============================================================================

# Verify all required command-line tools are available before benchmark starts.
# Fails early with a list of missing tools rather than failing mid-run.
require_commands() {
  local missing=0
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "[ERROR] Missing required command: $cmd" >&2
      missing=1
    fi
  done
  if [[ $missing -ne 0 ]]; then
    return 1
  fi
}

# ============================================================================
# Directory Layout
# ============================================================================

# Create canonical output directory structure for a benchmark run.
# Path: Dataset/x86_benchmark/<YYYYMMDD>/sr/<sampling_rate>/threshold/<threshold>/
# Returns the full path; exits on mkdir failure.
ensure_output_dir() {
  local sampling_rate="$1"
  local threshold="$2"
  local date_tag="$3"

  local out_dir="$DATA_ROOT/${date_tag}/sr/${sampling_rate}/threshold/${threshold}"
  mkdir -p "$out_dir" || {
    echo "[ERROR] Failed to create output directory: $out_dir" >&2
    return 1
  }
  printf "%s\n" "$out_dir"
}

# ============================================================================
# Log Archiving
# ============================================================================

# Move files matching a glob pattern to a destination, but only if matches exist.
# Prevents errors from attempting to move non-existent files.
archive_pattern_if_exists() {
  local pattern="$1"
  local destination="$2"

  shopt -s nullglob
  local matches=( $pattern )
  shopt -u nullglob

  if [[ ${#matches[@]} -gt 0 ]]; then
    command mv -f "${matches[@]}" "$destination/" 2>/dev/null || {
      echo "[WARN] Failed to move some logs matching $pattern to $destination" >&2
      return 1
    }
  fi
}

# Collect all artifacts from a benchmark configuration run and move them
# to the structured output directory.
# Called immediately after a single (sampling_rate, threshold) config finishes.
archive_configuration_logs() {
  local core="$1"
  local sampling_rate="$2"
  local threshold="$3"
  local destination="$4"

  if [[ ! -d "$destination" ]]; then
    echo "[ERROR] Output directory does not exist: $destination" >&2
    return 1
  fi

  pushd "$ROOT_DIR" >/dev/null

  # Archive frequency logs
  archive_pattern_if_exists "core_freq_*_${sampling_rate}_${threshold}_*.log" "$destination"
  archive_pattern_if_exists "cpu_cores_freq_*_${sampling_rate}_${threshold}_*.log" "$destination"

  # Archive utilization logs
  archive_pattern_if_exists "core_utilization_*_${sampling_rate}_${threshold}_*.log" "$destination"
  archive_pattern_if_exists "cpu_utilization_*_${sampling_rate}_${threshold}_*.log" "$destination"

  # Archive power and voltage logs
  archive_pattern_if_exists "cpu_power_*_${sampling_rate}_${threshold}_*.log" "$destination"
  archive_pattern_if_exists "cpu_cores_voltage_*_${sampling_rate}_${threshold}_*.log" "$destination"

  # Archive HPL output and timing logs
  archive_pattern_if_exists "hpl_*_${sampling_rate}_${threshold}_*.out" "$destination"
  archive_pattern_if_exists "mrt_times_*_${sampling_rate}_${threshold}_*.log" "$destination"

  popd >/dev/null

  echo "[INFO] Archived logs to: $destination"
}
