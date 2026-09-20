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

echo "==> Compile matrix operand staging RTL"
iverilog \
    -g2012 \
    -Wall \
    -s cgx1_matrix_operand_staging_tb \
    -o build/rtl/cgx1_matrix_operand_staging_tb.vvp \
    source/rtl/cgx1_matrix_operand_staging.sv \
    source/rtl/tests/cgx1_matrix_operand_staging_tb.sv

echo "==> Run matrix operand staging RTL"
vvp build/rtl/cgx1_matrix_operand_staging_tb.vvp

echo "==> Compile per-wave matrix scoreboard RTL"
iverilog \
    -g2012 \
    -Wall \
    -s cgx1_matrix_wave_scoreboard_tb \
    -o build/rtl/cgx1_matrix_wave_scoreboard_tb.vvp \
    source/rtl/cgx1_matrix_pipeline_control.sv \
    source/rtl/cgx1_matrix_wave_scoreboard.sv \
    source/rtl/tests/cgx1_matrix_wave_scoreboard_tb.sv

echo "==> Run per-wave matrix scoreboard RTL"
vvp build/rtl/cgx1_matrix_wave_scoreboard_tb.vvp

echo "==> Compile matrix output-result staging RTL"
iverilog \
    -g2012 \
    -Wall \
    -s cgx1_matrix_result_staging_tb \
    -o build/rtl/cgx1_matrix_result_staging_tb.vvp \
    source/rtl/cgx1_matrix_result_staging.sv \
    source/rtl/tests/cgx1_matrix_result_staging_tb.sv

echo "==> Run matrix output-result staging RTL"
vvp build/rtl/cgx1_matrix_result_staging_tb.vvp

echo "==> Compile matrix INT8 execution RTL"
iverilog \
    -g2012 \
    -Wall \
    -s cgx1_matrix_int8_execution_tb \
    -o build/rtl/cgx1_matrix_int8_execution_tb.vvp \
    source/rtl/cgx1_matrix_int8_execution.sv \
    source/rtl/tests/cgx1_matrix_int8_execution_tb.sv

echo "==> Run matrix INT8 execution RTL"
vvp build/rtl/cgx1_matrix_int8_execution_tb.vvp

echo "==> Compile integrated matrix INT8 path RTL"
iverilog \
    -g2012 \
    -Wall \
    -s cgx1_matrix_int8_path_tb \
    -o build/rtl/cgx1_matrix_int8_path_tb.vvp \
    source/rtl/cgx1_matrix_pipeline_control.sv \
    source/rtl/cgx1_matrix_operand_staging.sv \
    source/rtl/cgx1_matrix_int8_execution.sv \
    source/rtl/cgx1_matrix_result_staging.sv \
    source/rtl/cgx1_matrix_int8_path.sv \
    source/rtl/tests/cgx1_matrix_int8_path_tb.sv

echo "==> Run integrated matrix INT8 path RTL"
vvp build/rtl/cgx1_matrix_int8_path_tb.vvp

echo "[pass] CGX 1 RTL validation completed."
