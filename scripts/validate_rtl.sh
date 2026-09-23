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

echo "==> Compile signed INT8 matrix-engine shell RTL"
iverilog \
    -g2012 \
    -Wall \
    -s cgx1_matrix_int8_engine_shell_tb \
    -o build/rtl/cgx1_matrix_int8_engine_shell_tb.vvp \
    source/rtl/cgx1_matrix_pipeline_control.sv \
    source/rtl/cgx1_matrix_operand_staging.sv \
    source/rtl/cgx1_matrix_int8_execution.sv \
    source/rtl/cgx1_matrix_result_staging.sv \
    source/rtl/cgx1_matrix_int8_path.sv \
    source/rtl/cgx1_matrix_wave_scoreboard.sv \
    source/rtl/cgx1_matrix_int8_engine_shell.sv \
    source/rtl/tests/cgx1_matrix_int8_engine_shell_tb.sv

echo "==> Run signed INT8 matrix-engine shell RTL"
vvp build/rtl/cgx1_matrix_int8_engine_shell_tb.vvp

echo "==> Compile resident-wave VGPR storage RTL"
iverilog \
    -g2012 \
    -Wall \
    -s cgx1_resident_wave_vgpr_file_tb \
    -o build/rtl/cgx1_resident_wave_vgpr_file_tb.vvp \
    source/rtl/cgx1_resident_wave_vgpr_file.sv \
    source/rtl/tests/cgx1_resident_wave_vgpr_file_tb.sv

echo "==> Run resident-wave VGPR storage RTL"
vvp build/rtl/cgx1_resident_wave_vgpr_file_tb.vvp

echo "==> Compile resident-wave signed INT8 matrix-engine RTL"
iverilog \
    -g2012 \
    -Wall \
    -s cgx1_matrix_int8_resident_engine_tb \
    -o build/rtl/cgx1_matrix_int8_resident_engine_tb.vvp \
    source/rtl/cgx1_matrix_pipeline_control.sv \
    source/rtl/cgx1_matrix_operand_staging.sv \
    source/rtl/cgx1_matrix_int8_execution.sv \
    source/rtl/cgx1_matrix_result_staging.sv \
    source/rtl/cgx1_matrix_int8_path.sv \
    source/rtl/cgx1_matrix_wave_scoreboard.sv \
    source/rtl/cgx1_matrix_resident_wave_scoreboard.sv \
    source/rtl/cgx1_matrix_resident_wave_arbiter.sv \
    source/rtl/cgx1_matrix_int8_resident_engine.sv \
    source/rtl/tests/cgx1_matrix_int8_resident_engine_tb.sv

echo "==> Run resident-wave signed INT8 matrix-engine RTL"
vvp build/rtl/cgx1_matrix_int8_resident_engine_tb.vvp


echo "==> Compile privileged pooled VGPR restore mapping RTL"
iverilog \
    -g2012 \
    -Wall \
    -s cgx1_pooled_vgpr_restore_mapper_tb \
    -o build/rtl/cgx1_pooled_vgpr_restore_mapper_tb.vvp \
    source/rtl/cgx1_pooled_vgpr_restore_mapper.sv \
    source/rtl/tests/cgx1_pooled_vgpr_restore_mapper_tb.sv
echo "==> Run privileged pooled VGPR restore mapping RTL"
vvp build/rtl/cgx1_pooled_vgpr_restore_mapper_tb.vvp

echo "==> Compile pooled matrix VGPR preflight RTL"
iverilog \
    -g2012 \
    -Wall \
    -s cgx1_matrix_vgpr_preflight_tb \
    -o build/rtl/cgx1_matrix_vgpr_preflight_tb.vvp \
    source/rtl/cgx1_matrix_vgpr_allocation_guard.sv \
    source/rtl/cgx1_matrix_vgpr_preflight.sv \
    source/rtl/tests/cgx1_matrix_vgpr_preflight_tb.sv
echo "==> Run pooled matrix VGPR preflight RTL"
vvp build/rtl/cgx1_matrix_vgpr_preflight_tb.vvp

echo "==> Compile pooled resident-wave VGPR allocator RTL"
iverilog \
    -g2012 \
    -Wall \
    -s cgx1_resident_wave_vgpr_allocator_tb \
    -o build/rtl/cgx1_resident_wave_vgpr_allocator_tb.vvp \
    source/rtl/cgx1_pooled_vgpr_mapper.sv \
    source/rtl/cgx1_matrix_vgpr_allocation_guard.sv \
    source/rtl/cgx1_resident_wave_vgpr_allocator.sv \
    source/rtl/tests/cgx1_resident_wave_vgpr_allocator_tb.sv
echo "==> Run pooled resident-wave VGPR allocator RTL"
vvp build/rtl/cgx1_resident_wave_vgpr_allocator_tb.vvp

echo "==> Compile pooled VGPR storage RTL"
iverilog \
    -g2012 \
    -Wall \
    -s cgx1_pooled_vgpr_storage_tb \
    -o build/rtl/cgx1_pooled_vgpr_storage_tb.vvp \
    source/rtl/cgx1_pooled_vgpr_storage.sv \
    source/rtl/tests/cgx1_pooled_vgpr_storage_tb.sv
echo "==> Run pooled VGPR storage RTL"
vvp build/rtl/cgx1_pooled_vgpr_storage_tb.vvp

echo "==> Compile pooled matrix VGPR frontend RTL"
iverilog \
    -g2012 \
    -Wall \
    -s cgx1_matrix_pooled_vgpr_frontend_tb \
    -o build/rtl/cgx1_matrix_pooled_vgpr_frontend_tb.vvp \
    source/rtl/cgx1_pooled_vgpr_mapper.sv \
    source/rtl/cgx1_matrix_vgpr_allocation_guard.sv \
    source/rtl/cgx1_matrix_vgpr_preflight.sv \
    source/rtl/cgx1_matrix_pooled_vgpr_frontend.sv \
    source/rtl/tests/cgx1_matrix_pooled_vgpr_frontend_tb.sv
echo "==> Run pooled matrix VGPR frontend RTL"
vvp build/rtl/cgx1_matrix_pooled_vgpr_frontend_tb.vvp

echo "==> Compile pooled VGPR matrix subsystem RTL"
iverilog \
    -g2012 \
    -Wall \
    -s cgx1_pooled_vgpr_matrix_subsystem_tb \
    -o build/rtl/cgx1_pooled_vgpr_matrix_subsystem_tb.vvp \
    source/rtl/cgx1_pooled_vgpr_mapper.sv \
    source/rtl/cgx1_pooled_vgpr_restore_mapper.sv \
    source/rtl/cgx1_matrix_vgpr_allocation_guard.sv \
    source/rtl/cgx1_matrix_vgpr_preflight.sv \
    source/rtl/cgx1_matrix_request_preflight_array.sv \
    source/rtl/cgx1_resident_wave_vgpr_allocator.sv \
    source/rtl/cgx1_pooled_vgpr_storage.sv \
    source/rtl/cgx1_pooled_vgpr_matrix_subsystem.sv \
    source/rtl/tests/cgx1_pooled_vgpr_matrix_subsystem_tb.sv
echo "==> Run pooled VGPR matrix subsystem RTL"
vvp build/rtl/cgx1_pooled_vgpr_matrix_subsystem_tb.vvp

echo "==> Compile pooled resident-wave INT8 integration RTL"
iverilog \
    -g2012 \
    -Wall \
    -s cgx1_matrix_int8_pooled_resident_engine_tb \
    -o build/rtl/cgx1_matrix_int8_pooled_resident_engine_tb.vvp \
    source/rtl/cgx1_matrix_pipeline_control.sv \
    source/rtl/cgx1_matrix_operand_staging.sv \
    source/rtl/cgx1_matrix_int8_execution.sv \
    source/rtl/cgx1_matrix_result_staging.sv \
    source/rtl/cgx1_matrix_int8_path.sv \
    source/rtl/cgx1_matrix_wave_scoreboard.sv \
    source/rtl/cgx1_matrix_resident_wave_scoreboard.sv \
    source/rtl/cgx1_matrix_resident_wave_arbiter.sv \
    source/rtl/cgx1_matrix_int8_resident_engine.sv \
    source/rtl/cgx1_pooled_vgpr_mapper.sv \
    source/rtl/cgx1_pooled_vgpr_restore_mapper.sv \
    source/rtl/cgx1_matrix_vgpr_allocation_guard.sv \
    source/rtl/cgx1_matrix_vgpr_preflight.sv \
    source/rtl/cgx1_matrix_request_preflight_array.sv \
    source/rtl/cgx1_resident_wave_vgpr_allocator.sv \
    source/rtl/cgx1_pooled_vgpr_storage.sv \
    source/rtl/cgx1_pooled_vgpr_matrix_subsystem.sv \
    source/rtl/cgx1_matrix_int8_pooled_resident_engine.sv \
    source/rtl/tests/cgx1_matrix_int8_pooled_resident_engine_tb.sv
echo "==> Run pooled resident-wave INT8 integration RTL"
vvp build/rtl/cgx1_matrix_int8_pooled_resident_engine_tb.vvp


echo "==> Compile ordinary/shared pooled VGPR control RTL"
iverilog -g2012 -Wall -s cgx1_ordinary_shared_control_tb -o build/rtl/cgx1_ordinary_shared_control_tb.vvp \
    source/rtl/cgx1_pooled_vgpr_shared_port_arbiter.sv \
    source/rtl/cgx1_pooled_vgpr_release_guard.sv \
    source/rtl/cgx1_matrix_mixed_workload_admission.sv \
    source/rtl/tests/cgx1_ordinary_shared_control_tb.sv
echo "==> Run ordinary/shared pooled VGPR control RTL"
vvp build/rtl/cgx1_ordinary_shared_control_tb.vvp

echo "==> Compile ordinary same-bank read sequencer RTL"
iverilog -g2012 -Wall -s cgx1_ordinary_read_sequencer_tb -o build/rtl/cgx1_ordinary_read_sequencer_tb.vvp \
    source/rtl/cgx1_pooled_vgpr_ordinary_read_sequencer.sv \
    source/rtl/tests/cgx1_ordinary_read_sequencer_tb.sv
echo "==> Run ordinary same-bank read sequencer RTL"
vvp build/rtl/cgx1_ordinary_read_sequencer_tb.vvp

echo "==> Compile vector INT32 ALU RTL"
iverilog -g2012 -Wall -s cgx1_vector_int32_alu_tb -o build/rtl/cgx1_vector_int32_alu_tb.vvp \
    source/rtl/cgx1_vector_int32_alu.sv \
    source/rtl/tests/cgx1_vector_int32_alu_tb.sv
echo "==> Run vector INT32 ALU RTL"
vvp build/rtl/cgx1_vector_int32_alu_tb.vvp

echo "==> Compile vector INT32 pipeline RTL"
iverilog -g2012 -Wall -s cgx1_vector_int32_pipeline_tb -o build/rtl/cgx1_vector_int32_pipeline_tb.vvp \
    source/rtl/cgx1_vector_int32_alu.sv \
    source/rtl/cgx1_vector_int32_pipeline.sv \
    source/rtl/tests/cgx1_vector_int32_pipeline_tb.sv
echo "==> Run vector INT32 pipeline RTL"
vvp build/rtl/cgx1_vector_int32_pipeline_tb.vvp

echo "==> Compile resident vector scheduler RTL"
iverilog -g2012 -Wall -s cgx1_vector_resident_wave_scheduler_tb -o build/rtl/cgx1_vector_resident_wave_scheduler_tb.vvp \
    source/rtl/cgx1_vector_resident_wave_scheduler.sv \
    source/rtl/tests/cgx1_vector_resident_wave_scheduler_tb.sv
echo "==> Run resident vector scheduler RTL"
vvp build/rtl/cgx1_vector_resident_wave_scheduler_tb.vvp

echo "==> Compile unified pooled execution subsystem RTL"
iverilog -g2012 -Wall -s cgx1_pooled_vgpr_execution_subsystem_tb -o build/rtl/cgx1_pooled_vgpr_execution_subsystem_tb.vvp \
    source/rtl/cgx1_pooled_vgpr_mapper.sv \
    source/rtl/cgx1_pooled_vgpr_restore_mapper.sv \
    source/rtl/cgx1_matrix_vgpr_allocation_guard.sv \
    source/rtl/cgx1_matrix_vgpr_preflight.sv \
    source/rtl/cgx1_matrix_request_preflight_array.sv \
    source/rtl/cgx1_resident_wave_vgpr_allocator.sv \
    source/rtl/cgx1_pooled_vgpr_storage.sv \
    source/rtl/cgx1_pooled_vgpr_ordinary_frontend.sv \
    source/rtl/cgx1_pooled_vgpr_ordinary_read_sequencer.sv \
    source/rtl/cgx1_pooled_vgpr_shared_port_arbiter.sv \
    source/rtl/cgx1_pooled_vgpr_release_guard.sv \
    source/rtl/cgx1_pooled_vgpr_execution_subsystem.sv \
    source/rtl/tests/cgx1_pooled_vgpr_execution_subsystem_tb.sv
echo "==> Run unified pooled execution subsystem RTL"
vvp build/rtl/cgx1_pooled_vgpr_execution_subsystem_tb.vvp

echo "[pass] CGX 1 RTL validation completed."
