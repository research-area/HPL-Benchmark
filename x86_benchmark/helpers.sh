#!/bin/bash

set -euo pipefail

# ============================================================================
# HPL x86 Benchmark Helpers
# Power modeling and per-core voltage/frequency helpers for ondemand governor
# benchmarking on x86 systems with Intel CPUs.
# ============================================================================

# Reads per-core voltage using MSR 0x198 (Intel only).
# MSR 0x198 contains the core VID; we extract bits [47:32] and scale by 1/8192.
# Returns "N/A" if rdmsr fails or is unavailable.
read_cpu_voltage_msr() {
  local core="$1"
  local raw=""

  raw=$(sudo rdmsr -p "$core" 0x198 -u --bitfield 47:32 2>/dev/null || true)
  if [[ -z "$raw" ]]; then
    echo "N/A"
    return
  fi

  local voltage
  voltage=$(echo "scale=3; $raw / 8192" | bc -l)
  if awk "BEGIN {exit !($voltage > 0)}"; then
    echo "$voltage"
  else
    echo "0"
  fi
}

# Piecewise-linear model for whole-CPU idle power as a function of frequency.
# Calibrated for x86 Xeon/Core systems; interpolates between known frequency points.
# Frequency in Hz; returns power in Watts.
interpolate_cpu_idle_power() {
  local freq_hz="$1"
  freq_hz=$(printf "%.0f" "$freq_hz")

  awk -v f="$freq_hz" '
  BEGIN {
    fq[1]=800000; pw[1]=7.14;
    fq[2]=1450000; pw[2]=7.35;
    fq[3]=2100000; pw[3]=7.49;
    n=3;

    if (f <= fq[1]) { printf "%.6f", pw[1]; exit }
    if (f >= fq[n]) { printf "%.6f", pw[n]; exit }

    for (i=1; i<n; i++) {
      if (f >= fq[i] && f <= fq[i+1]) {
        power = pw[i] + (f - fq[i]) * (pw[i+1] - pw[i]) / (fq[i+1] - fq[i]);
        printf "%.6f", power;
        exit
      }
    }

    printf "%.6f", pw[1]
  }'
}

# Dynamic power model for whole CPU: P = Ceff * V^2 * f.
# Ceff is a calibrated effective capacitance constant.
# Frequency in kHz; voltage in Volts; returns power in Watts.
compute_cpu_p_dynamic() {
  local freq_khz="$1"
  local volt="$2"
  local ceff="0.0000172773"

  freq_khz=$(printf "%.0f" "$freq_khz")
  if [[ -z "$freq_khz" || -z "$volt" ]]; then
    echo "0"
    return
  fi

  bc -l <<< "scale=10; $ceff * $volt^2 * $freq_khz"
}

# Core-level modeled power derived from whole-CPU idle/dynamic components.
# Distributes idle power proportionally; scales dynamic power by measured utilization.
# Returns estimated core power in Watts.
modeled_power() {
  local core_freq="$1"
  local core_volt="$2"
  local core_util="$3"
  local number_of_cores="$4"

  local cpu_idle_power
  local cpu_dynamic_power
  cpu_idle_power=$(interpolate_cpu_idle_power "$core_freq")
  cpu_dynamic_power=$(compute_cpu_p_dynamic "$core_freq" "$core_volt")

  local core_idle_power
  local core_dynamic_power
  core_idle_power=$(echo "$cpu_idle_power / $number_of_cores" | bc -l)
  core_dynamic_power=$(echo "$cpu_dynamic_power / $number_of_cores" | bc -l)

  echo "$(echo "$core_idle_power + ($core_util / 100) * $core_dynamic_power" | bc -l)"
}
