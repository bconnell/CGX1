#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
for tool in verilator yosys timeout; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool is required for the RTL tools lane." >&2
        exit 1
    fi
done

python3 scripts/check_disk_budget.py \
    --operation rtl-tools --output-path build/rtl-tools --scan-root build/rtl-tools

mkdir -p build/rtl-tools/logs
rtl_sources=(source/rtl/*.sv)
verilator_tops=(
    cgx1_top
    cgx1_matrix_vector_issue_arbiter
    cgx1_pooled_vgpr_matrix_subsystem
    cgx1_compute_workgroup_execution_frontend
    cgx1_compute_workgroup_lsu
)
: > build/rtl-tools/verilator-logs.list
for top in "${verilator_tops[@]}"; do
    log="build/rtl-tools/logs/verilator-${top}.log"
    echo "==> Bounded Verilator lint/elaboration: ${top}"
    if ! timeout --signal=TERM --kill-after=5s 90s verilator --lint-only --timing --Wno-fatal \
        --top-module "$top" "${rtl_sources[@]}" >"$log" 2>&1; then
        cat "$log" >&2
        echo "[fail] Verilator lint/elaboration failed for ${top}; log=${log}" >&2
        exit 1
    fi
    cat "$log"
    printf '%s\n' "$log" >> build/rtl-tools/verilator-logs.list
done

verilator_args=()
while IFS= read -r log; do verilator_args+=(--verilator-log "$log"); done < build/rtl-tools/verilator-logs.list

formal_log="build/rtl-tools/logs/yosys-formal-issue-arbiter.log"
python3 scripts/check_disk_budget.py \
    --operation formal --output-path "$formal_log"
echo "==> Bounded Yosys assertion proof: matrix/vector issue arbitration truth table"
if ! timeout --signal=TERM --kill-after=5s 90s yosys -Q -p \
    'read_verilog -formal -sv source/rtl/cgx1_matrix_vector_issue_arbiter.sv source/rtl/formal/cgx1_matrix_vector_issue_arbiter_formal.sv; prep -top cgx1_matrix_vector_issue_arbiter_formal -flatten; sat -prove-asserts -verify -show-ports' \
    >"$formal_log" 2>&1; then
    cat "$formal_log" >&2
    echo "[fail] Yosys assertion proof failed; log=${formal_log}" >&2
    exit 1
fi
cat "$formal_log"

synthesis_log="build/rtl-tools/logs/yosys-synthesis-issue-arbiter.log"
python3 scripts/check_disk_budget.py \
    --operation synthesis-smoke --output-path "$synthesis_log"
echo "==> Bounded Yosys synthesis smoke: matrix/vector issue arbitration"
if ! timeout --signal=TERM --kill-after=5s 90s yosys -Q -p \
    'read_verilog -sv source/rtl/cgx1_matrix_vector_issue_arbiter.sv; hierarchy -check -top cgx1_matrix_vector_issue_arbiter; proc; opt; check; stat' \
    >"$synthesis_log" 2>&1; then
    cat "$synthesis_log" >&2
    echo "[fail] Yosys synthesis smoke failed; log=${synthesis_log}" >&2
    exit 1
fi
cat "$synthesis_log"

python3 scripts/validate_rtl_tool_warnings.py "${verilator_args[@]}" \
    --yosys-log "$formal_log" --yosys-log "$synthesis_log"
python3 scripts/check_disk_budget.py \
    --operation rtl-tools --output-path build/rtl-tools --scan-root build/rtl-tools
echo "[pass] Bounded Verilator lint, Yosys assertion proof, and representative synthesis smoke completed."
