#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! command -v iverilog >/dev/null 2>&1; then
    echo "iverilog is required for RTL validation." >&2
    exit 1
fi

if ! command -v vvp >/dev/null 2>&1; then
    echo "vvp is required for RTL validation." >&2
    exit 1
fi

echo "==> Icarus Verilog version"
iverilog -V

mkdir -p build/rtl

echo "==> Compile matrix pipeline control RTL"
iverilog     -g2012     -Wall     -s cgx1_matrix_pipeline_control_tb     -o build/rtl/cgx1_matrix_pipeline_control_tb.vvp     source/rtl/cgx1_matrix_pipeline_control.sv     source/rtl/tests/cgx1_matrix_pipeline_control_tb.sv

echo "==> Run matrix pipeline control RTL"
vvp build/rtl/cgx1_matrix_pipeline_control_tb.vvp

echo "[pass] CGX 1 RTL validation completed."
