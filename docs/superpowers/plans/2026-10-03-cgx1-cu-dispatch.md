# CGX1 CU Dispatch Scheduler Implementation Plan

## Scope and fixed boundaries

Build the next completeness increment at the decoded workgroup-dispatch boundary. A CU-local scheduler accepts already decoded workgroup demands tagged with queue-context identity and priority, consults externally supplied tile eligibility, and delegates all complete-workgroup reservations to `ComputeUnitWorkgroupScheduler`. Temporary CU resource pressure keeps requests pending; demands that can never fit return an explicit terminal admission result. Workgroup execution, barriers, LSU waits, and quiescent release remain owned by the existing residency scheduler and RTL frontend.

The repository contract remains authoritative: queue contexts are a device-wide target of 64 across graphics and compute; there are eight priority levels; queue identity carries process/address-space identity, engine class, and fault state; compute preemption remains at workgroup boundaries; tile eligibility comes from the power manager. This increment does not define command packets, ring parsing, global queue-context allocation, multi-tile placement, graphics dispatch, or runtime/compiler ABI.

The reference will make its test policy explicit and configurable: numeric priority 0 is lowest and 7 is highest, per-level service weights are supplied by policy, and aging promotes a continuously waiting context after a configurable number of eligible scheduler cycles. Per-context FIFO ordering is preserved. The scheduler attempts at most one descriptor per cycle and may advance to another context after a transient resource rejection. These policy values are reference defaults, not calibrated performance claims.

## Files and responsibilities

- `source/model/cu_dispatch_scheduler.hpp`: queue-context identity, bounded per-context pending work, priority/aging selection, admission-result classification, and composition with the existing CU residency owner.
- `source/model/cu_dispatch_scheduler_tests.cpp`: executable policy, resource-pressure, lifecycle, and randomized regression coverage using real workgroup admission.
- `source/model/CMakeLists.txt`: register the focused executable test target.
- `source/rtl/cgx1_compute_workgroup_dispatch_scheduler.sv`: RTL ingress queue and dispatch handshake around the authoritative workgroup frontend, with tile eligibility, per-context ordering, temporary retry, and explicit terminal completion.
- `source/rtl/tests/cgx1_compute_workgroup_dispatch_scheduler_tb.sv`: standalone RTL tests for buffering, selection, pressure retry, failure propagation, reset, and queue fairness.
- `scripts/validate_rtl.sh`: include the standalone scheduler testbench in the repository RTL gate.
- `docs/SCHEDULING_PREEMPTION.md`, `docs/STATUS.md`, `docs/VALIDATION.md`, `docs/ROADMAP.md`, and `design/cgx1_completeness_matrix.json`: document only behavior and evidence completed on this candidate.

## Implementation tasks

1. Add focused C++ tests first. Cover queue identity and limits, FIFO, weight arbitration, aging starvation resistance, tile ineligibility, transient resource retry, terminal impossible-demand reporting, completion/resource release, reset, and deterministic randomized enqueue/dispatch/retirement sequences. Run the new target and confirm it fails because the scheduler API is absent.
2. Implement the smallest C++ scheduler API that passes those tests. Preserve exact queue/process/address-space identity. Classify only resource-unavailable/fragmented failures as retryable; reject malformed or capacity-impossible demands. Delegate resident lifecycle and issue eligibility to `ComputeUnitWorkgroupScheduler`.
3. Add the RTL ingress scheduler and standalone testbench. Exercise its request payload stability under backpressure, queue ordering, priority aging, temporary admission retry, permanent failure completion, tile masking, reset, and bounded queue-full behavior.
4. Integrate the RTL module into the existing workgroup frontend/test boundary without duplicating VGPR, memory-region, barrier, or power eligibility ownership. Run focused C++ and RTL tests, then complete repository gates.
5. Update public status, scheduling, roadmap, validation, and completeness evidence. Review staged diff and exact-candidate fingerprint, commit locally, verify clean state, and do not push.

## Validation and evidence limits

Use the new focused executable test as the RED/GREEN proof, the full CMake/CTest suite, the focused scheduler RTL simulation, and the full `scripts/validate_rtl.sh` gate. Run repository integrity/design checks and the Windows wrapper where available. Report exact command outcomes and distinguish environment/toolchain limits from product failures. Do not claim command ABI, global queue-manager, multi-tile, hosted-CI, synthesis, timing, area, power, physical-implementation, or silicon validation from this increment.

## Completion record

- [x] C++ queue policy/reference and 600 deterministic randomized scheduling cycles.
- [x] Standalone RTL queue selection, retry/terminal completion, fault, aging, payload identity, and reset checks.
- [x] RTL integration with the actual workgroup frontend, including admission, transient retry, quiescent resource release, and retry success.
- [x] `cmake --build build -j2` and `ctest --test-dir build --output-on-failure`: all 25 tests passed under Ubuntu WSL.
- [x] `bash scripts/validate_rtl.sh`: passed under Ubuntu WSL with Icarus Verilog 12.0.
- [x] Windows wrapper: hygiene, integrity, design consistency, negative controls, and Markdown links passed; native CMake could not start because `cmake.exe` is unavailable on Windows PATH.

The exact scope remains one CU's decoded compute workgroup ingress. The I/O-die global manager, command packet ABI, graphics dispatch, multi-CU placement, runtime/compiler integration, hosted CI, and physical implementation remain outside this checkpoint.
