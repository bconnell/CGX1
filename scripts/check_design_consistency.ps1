param(
    [string]$ArchitecturePath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($ArchitecturePath)) {
    $ArchitecturePath = Join-Path $repoRoot "design\cgx1_architecture.json"
} else {
    $ArchitecturePath = (Resolve-Path $ArchitecturePath).Path
}

$architecture = Get-Content -LiteralPath $ArchitecturePath -Raw | ConvertFrom-Json
$findings = New-Object System.Collections.Generic.List[string]
$invariant = [Globalization.CultureInfo]::InvariantCulture
$multiply = [char]0x00D7

function Add-Finding {
    param([string]$Message)
    $findings.Add($Message)
}

function Format-Number {
    param([object]$Value)
    return ([double]$Value).ToString("0.###", $invariant)
}

function Require-Literal {
    param([string]$RelativePath, [string]$Expected)

    $path = Join-Path $repoRoot ($RelativePath.Replace("/", "\"))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Finding "$($RelativePath): file is missing"
        return
    }

    $text = [IO.File]::ReadAllText($path)
    if (-not $text.Contains($Expected)) {
        Add-Finding "$($RelativePath): expected value is missing: $Expected"
    }
}

$length = Format-Number $architecture.mechanical_mm.length
$height = Format-Number $architecture.mechanical_mm.height
$thickness = Format-Number $architecture.mechanical_mm.thickness
$dockLength = Format-Number $architecture.dock_mechanical_mm.length
$dockWidth = Format-Number $architecture.dock_mechanical_mm.width
$dockHeight = Format-Number $architecture.dock_mechanical_mm.height
$fanThickness = Format-Number $architecture.cooling.card_fan_mm.thickness

$fullPower = Format-Number $architecture.power_w.dock_full
$slotMax = Format-Number $architecture.power_w.slot_max
$safeBoot = Format-Number $architecture.power_w.safe_boot
$slotEco = Format-Number $architecture.power_w.slot_eco
$dockQuiet = Format-Number $architecture.power_w.dock_quiet
$dockFallback = Format-Number $architecture.power_w.dock_fault_fallback

$lanes = Format-Number $architecture.silicon.total_fp32_lanes
$peakClock = ([double]$architecture.silicon.peak_clock_ghz).ToString("0.00", $invariant)
$fp32 = ([double]$architecture.silicon.peak_fp32_tflops).ToString("0.00", $invariant)
$memory = ([double]$architecture.memory.peak_bandwidth_tbps).ToString("0.0", $invariant)
$vram = Format-Number $architecture.memory.capacity_gb
$wave = Format-Number $architecture.execution_model.native_wave_size
$simdPartitions = Format-Number $architecture.execution_model.simd_partitions_per_compute_unit
$lanesPerSimd = Format-Number $architecture.execution_model.lanes_per_simd_partition
$texturePerTile = Format-Number $architecture.texture_subsystem.texture_blocks_per_tile
$textureTotal = Format-Number $architecture.texture_subsystem.texture_blocks_total
$textureSamples = Format-Number $architecture.texture_subsystem.bilinear_samples_per_block_per_cycle
$rasterPerTile = Format-Number $architecture.graphics_pipeline.raster_partitions_per_tile
$ropPerTile = Format-Number $architecture.graphics_pipeline.rop_lanes_per_tile
$fabricRead = Format-Number $architecture.chiplet_fabric.aggregate_read_payload_target_tbps
$queueContexts = Format-Number $architecture.scheduler.resident_hardware_queue_contexts
$priorityLevels = Format-Number $architecture.scheduler.priority_levels
$preferredPage = Format-Number $architecture.virtual_memory.preferred_vram_page_bytes
$l1Shared = Format-Number $architecture.cache.l1_shared_kb_per_compute_unit
$l2PerTile = Format-Number $architecture.cache.l2_mb_per_tile
$l2Total = Format-Number $architecture.cache.l2_total_mb
$packageCache = Format-Number $architecture.cache.package_cache_mb
$computeTiles = Format-Number $architecture.silicon.compute_tiles
$matrixEnginesPerCu = Format-Number $architecture.silicon.matrix_engines_per_compute_unit
$matrixScope = [string]$architecture.matrix_engine.cooperative_scope_target
$matrixTileM = [int]$architecture.matrix_engine.tile_shapes.fp16_bf16.m
$matrixTileN = [int]$architecture.matrix_engine.tile_shapes.fp16_bf16.n
$matrixFp16K = [int]$architecture.matrix_engine.tile_shapes.fp16_bf16.k
$matrixFp8K = [int]$architecture.matrix_engine.tile_shapes.fp8_int8.k
$matrixSourceRegisters = [int]$architecture.matrix_engine.fragment_registers_per_lane.source_a
$matrixAccumulatorRegisters = [int]$architecture.matrix_engine.fragment_registers_per_lane.accumulator_result
$matrixCaptureCycles = [int]$architecture.matrix_engine.pipeline.register_capture_cycles
$matrixExecutionCycles = [int]$architecture.matrix_engine.pipeline.execution_cycles
$matrixWritebackCycles = [int]$architecture.matrix_engine.pipeline.writeback_cycles
$matrixIssueInterval = [int]$architecture.matrix_engine.pipeline.issue_interval_cycles
$matrixResultLatency = [int]$architecture.matrix_engine.pipeline.result_latency_cycles
$matrixWaveRegisterReads = [int]$architecture.matrix_engine.pipeline.wave_register_reads_per_capture_cycle
$matrixWaveRegisterWrites = [int]$architecture.matrix_engine.pipeline.wave_register_writes_per_writeback_cycle
$matrixWaveRegisterBits = [int]$architecture.matrix_engine.pipeline.wave_register_width_bits
$matrixInputStageBytes = [int]$architecture.matrix_engine.staging_bytes.total_input
$matrixActiveExecutionBytes = [int]$architecture.matrix_engine.staging_storage.active_execution_operand_bytes
$matrixOutputStageBytes = [int]$architecture.matrix_engine.staging_storage.output_result_slot_bytes
$matrixLogicalStoragePerEngine = [int]$architecture.matrix_engine.staging_storage.logical_pipeline_storage_bytes_per_engine
$matrixLogicalStoragePerCu = [int]$architecture.matrix_engine.staging_storage.logical_pipeline_storage_bytes_per_compute_unit
$matrixBankClasses = [int]$architecture.matrix_engine.register_banking.bank_classes_per_lane
$matrixSourceABankClass = [int]$architecture.matrix_engine.register_banking.source_a_base_modulo_8
$matrixSourceBBankClass = [int]$architecture.matrix_engine.register_banking.source_b_base_modulo_8
$matrixDestinationBankClass = [int]$architecture.matrix_engine.register_banking.accumulator_result_base_modulo_8
$pmVoltageMin = ([double]$architecture.power_management.core_voltage_target_range_v.min).ToString("0.00", $invariant)
$pmVoltageMax = ([double]$architecture.power_management.core_voltage_target_range_v.max).ToString("0.00", $invariant)
$p0TileCap = [string]$architecture.power_management.max_tile_state_by_board_state.P0
$p1TileCap = [string]$architecture.power_management.max_tile_state_by_board_state.P1
$p2TileCap = [string]$architecture.power_management.max_tile_state_by_board_state.P2
$p3TileCap = [string]$architecture.power_management.max_tile_state_by_board_state.P3
$p4TileCap = [string]$architecture.power_management.max_tile_state_by_board_state.P4

Require-Literal "README.md" ("| Card PCB | **$length " + $multiply + " $height mm** |")
Require-Literal "README.md" "| Installed thickness | **$thickness mm, dual slot** |"
Require-Literal "README.md" "| Full performance power | **$fullPower W nominal** |"
Require-Literal "README.md" "| Peak memory bandwidth | **$memory TB/s** |"
Require-Literal "README.md" "| FP32 lanes | 25,600 |"
Require-Literal "README.md" "| Peak FP32 target | $fp32 TFLOPS |"
Require-Literal "README.md" "| VRAM baseline | $vram GB HBM4 |"
Require-Literal "README.md" ("| Dock envelope | **$dockLength " + $multiply + " $dockWidth " + $multiply + " $dockHeight mm** |")

Require-Literal "mechanical/cgx1_card.scad" "pcb_l = $length;"
Require-Literal "mechanical/cgx1_card.scad" "pcb_h = $height;"
Require-Literal "mechanical/cgx1_card.scad" "card_t = $thickness;"
Require-Literal "mechanical/cgx1_card.scad" "fan_t = $fanThickness;"
Require-Literal "mechanical/cgx1_dock.scad" "dock_l = $dockLength;"
Require-Literal "mechanical/cgx1_dock.scad" "dock_w = $dockWidth;"
Require-Literal "mechanical/cgx1_dock.scad" "dock_h = $dockHeight;"
Require-Literal "mechanical/cgx1_dock.scad" "radiator_l = 280;"
Require-Literal "mechanical/cgx1_dock.scad" "pump_l = 112;"

Require-Literal "source/firmware/cgx1_power.c" "return $($safeBoot)U;"
Require-Literal "source/firmware/cgx1_power.c" "return $($slotEco)U;"
Require-Literal "source/firmware/cgx1_power.c" "return $($slotMax)U;"
Require-Literal "source/firmware/cgx1_power.c" "return $($dockQuiet)U;"
Require-Literal "source/firmware/cgx1_power.c" "return $($fullPower)U;"
Require-Literal "source/firmware/test_power.c" "telemetry.coolantFlowValid = false;"
Require-Literal "source/firmware/test_power.c" "telemetry.external48VPresent = false;"
Require-Literal "source/rtl/cgx1_top.sv" "active_power_state <= P0;"
Require-Literal "source/rtl/cgx1_top.sv" "tile_enable <= '0;"

Require-Literal "source/model/model.hpp" "kTargetLengthMm = $length;"
Require-Literal "source/model/model.hpp" "kTargetHeightMm = $height;"
Require-Literal "source/model/model.hpp" "kTargetThicknessMm = $thickness;"
Require-Literal "source/model/model.hpp" "kTargetFp32Lanes = $($lanes).0;"
Require-Literal "source/model/model.hpp" "kTargetPeakClockGhz = $peakClock;"
Require-Literal "source/model/model.hpp" "kTargetPeakFp32Tflops = $fp32;"
Require-Literal "source/model/model.hpp" "kTargetMemoryTbps = $memory;"
Require-Literal "source/model/model.hpp" "kTargetBoardPowerWatts = $($fullPower).0;"
Require-Literal "source/model/model.hpp" "kTargetVramGb = $($vram).0;"
Require-Literal "source/model/model.hpp" "kNativeWaveSize = $wave;"
Require-Literal "source/model/model.hpp" "kSimdPartitionsPerCu = $simdPartitions;"
Require-Literal "source/model/model.hpp" "kLanesPerSimdPartition = $lanesPerSimd;"
Require-Literal "source/model/model.hpp" "kTextureBlocksPerTile = $texturePerTile;"
Require-Literal "source/model/model.hpp" "kTextureBlocksTotal = $textureTotal;"
Require-Literal "source/model/model.hpp" "kBilinearSamplesPerTextureBlockPerCycle = $textureSamples;"
Require-Literal "source/model/model.hpp" "kRasterPartitionsPerTile = $rasterPerTile;"
Require-Literal "source/model/model.hpp" "kRopLanesPerTile = $ropPerTile;"
Require-Literal "source/model/model.hpp" "kFabricAggregateReadTbps = $fabricRead;"
Require-Literal "source/model/model.hpp" "kResidentHardwareQueueContexts = $queueContexts;"
Require-Literal "source/model/model.hpp" "kSchedulerPriorityLevels = $priorityLevels;"
Require-Literal "source/model/model.hpp" "kPreferredVramPageBytes = $preferredPage;"
Require-Literal "source/model/model.hpp" "kL1SharedKbPerComputeUnit = $l1Shared;"
Require-Literal "source/model/model.hpp" "kL2MbPerTile = $l2PerTile;"
Require-Literal "source/model/model.hpp" "kL2TotalMb = $l2Total;"
Require-Literal "source/model/model.hpp" "kPackageCacheMb = $packageCache;"
Require-Literal "source/isa/cgx1_isa.hpp" "InstructionClass::Extended"
Require-Literal "source/matrix/cgx1_matrix.hpp" "kMatrixEnginesPerComputeUnit = $($matrixEnginesPerCu)U;"
Require-Literal "source/matrix/cgx1_matrix.hpp" "kNativeWaveSize = $($wave)U;"
Require-Literal "source/matrix/cgx1_matrix.hpp" "kThroughputFrozen = true;"
Require-Literal "source/matrix/cgx1_matrix.hpp" "kPhysicalTileShapesFrozen = true;"
Require-Literal "source/matrix/cgx1_matrix.hpp" "kPhysicalFragmentMappingFrozen = true;"
Require-Literal "source/matrix/cgx1_matrix.hpp" "kMatrixInstructionEncodingFrozen = true;"
Require-Literal "source/matrix/cgx1_matrix.hpp" "kFloatingReductionOrderFrozen = true;"
Require-Literal "source/matrix/cgx1_matrix_architecture.hpp" "kMatrixTileM = $($matrixTileM)U;"
Require-Literal "source/matrix/cgx1_matrix_architecture.hpp" "kMatrixTileN = $($matrixTileN)U;"
Require-Literal "source/matrix/cgx1_matrix_architecture.hpp" "kFp16Bf16TileK = $($matrixFp16K)U;"
Require-Literal "source/matrix/cgx1_matrix_architecture.hpp" "kFp8Int8TileK = $($matrixFp8K)U;"
Require-Literal "source/matrix/cgx1_matrix_architecture.hpp" "kMatrixSourceRegistersPerLane = $($matrixSourceRegisters)U;"
Require-Literal "source/matrix/cgx1_matrix_architecture.hpp" "kMatrixAccumulatorRegistersPerLane = $($matrixAccumulatorRegisters)U;"
Require-Literal "source/matrix/cgx1_matrix_architecture.hpp" "kMatrixRegisterCaptureCycles = $($matrixCaptureCycles)U;"
Require-Literal "source/matrix/cgx1_matrix_architecture.hpp" "kMatrixExecutionCycles = $($matrixExecutionCycles)U;"
Require-Literal "source/matrix/cgx1_matrix_architecture.hpp" "kMatrixWritebackCycles = $($matrixWritebackCycles)U;"
Require-Literal "source/matrix/cgx1_matrix_architecture.hpp" "kMatrixIssueIntervalCycles = $($matrixIssueInterval)U;"
Require-Literal "source/matrix/cgx1_matrix_architecture.hpp" "kMatrixResultLatencyCycles = $($matrixResultLatency)U;"
Require-Literal "source/matrix/cgx1_matrix_architecture.hpp" "kMatrixWaveRegisterReadsPerCaptureCycle = $($matrixWaveRegisterReads)U;"
Require-Literal "source/matrix/cgx1_matrix_architecture.hpp" "kMatrixWaveRegisterWritesPerWritebackCycle = $($matrixWaveRegisterWrites)U;"
Require-Literal "source/matrix/cgx1_matrix_architecture.hpp" "kMatrixRegisterBankClasses = $($matrixBankClasses)U;"
Require-Literal "source/matrix/cgx1_matrix_architecture.hpp" "kMatrixSourceABaseModulo = $($matrixSourceABankClass)U;"
Require-Literal "source/matrix/cgx1_matrix_architecture.hpp" "kMatrixSourceBBaseModulo = $($matrixSourceBBankClass)U;"
Require-Literal "source/matrix/cgx1_matrix_banking.hpp" "kMatrixRegisterBankMask ="
Require-Literal "source/matrix/cgx1_matrix_pipeline.hpp" "kMatrixInputStageBytes ="
Require-Literal "source/rtl/cgx1_matrix_pipeline_control.sv" "localparam integer MATRIX_CAPTURE_CYCLES = $matrixCaptureCycles;"
Require-Literal "source/rtl/cgx1_matrix_pipeline_control.sv" "localparam integer MATRIX_EXECUTE_CYCLES = $matrixExecutionCycles;"
Require-Literal "source/rtl/cgx1_matrix_pipeline_control.sv" "localparam integer MATRIX_WRITEBACK_CYCLES = $matrixWritebackCycles;"
Require-Literal "source/rtl/cgx1_matrix_pipeline_control.sv" "localparam integer MATRIX_ISSUE_INTERVAL_CYCLES = $matrixIssueInterval;"
Require-Literal "source/rtl/cgx1_matrix_pipeline_control.sv" "localparam integer MATRIX_REGISTER_BANK_CLASSES = $matrixBankClasses;"
Require-Literal "source/rtl/cgx1_matrix_pipeline_control.sv" "localparam logic [2:0] MATRIX_SOURCE_A_BANK_CLASS = 3'd$matrixSourceABankClass;"
Require-Literal "source/rtl/cgx1_matrix_pipeline_control.sv" "localparam logic [2:0] MATRIX_SOURCE_B_BANK_CLASS = 3'd$matrixSourceBBankClass;"
Require-Literal "source/rtl/cgx1_matrix_pipeline_control.sv" "output logic       issue_dependency_hazard,"
Require-Literal "source/rtl/cgx1_matrix_pipeline_control.sv" "output logic [7:0] issue_accepted_d_base,"
Require-Literal "source/rtl/cgx1_matrix_pipeline_control.sv" "output logic [7:0] issue_accepted_a_base,"
Require-Literal "source/rtl/cgx1_matrix_pipeline_control.sv" "output logic [7:0] issue_accepted_b_base,"
Require-Literal "source/matrix/cgx1_matrix_pipeline.hpp" "MatrixDependsOnPendingDestination("
Require-Literal "source/matrix/cgx1_matrix_pipeline.hpp" "kWaveRegisterBits ="
Require-Literal "source/matrix/cgx1_matrix_staging.hpp" "kMatrixActiveExecutionOperandBytes ="
Require-Literal "source/matrix/cgx1_matrix_staging.hpp" "kMatrixLogicalPipelineStorageBytesPerEngine ="
Require-Literal "source/rtl/cgx1_matrix_pipeline_control.sv" "output logic [2:0] capture_cycle_index,"
Require-Literal "source/rtl/cgx1_matrix_pipeline_control.sv" "output logic [2:0] writeback_cycle_index,"
Require-Literal "source/rtl/cgx1_matrix_pipeline_control.sv" "output logic [4:0] execute_cycle_index,"
Require-Literal "source/rtl/cgx1_matrix_pipeline_control.sv" "output logic [3:0] execute_opcode,"
Require-Literal "source/rtl/cgx1_matrix_operand_staging.sv" "output logic [4095:0] active_a_words,"
Require-Literal "source/rtl/cgx1_matrix_operand_staging.sv" "output logic [8191:0] active_c_words"
Require-Literal "source/matrix/cgx1_matrix_scoreboard.hpp" "kMatrixScoreboardRegisterCount = 256U;"
Require-Literal "source/matrix/cgx1_matrix_scoreboard.hpp" "EvaluateOrdinaryIssueAgainstMatrix("
Require-Literal "source/rtl/cgx1_matrix_wave_scoreboard.sv" "input  logic [7:0]   matrix_accepted_d_base,"
Require-Literal "source/rtl/cgx1_matrix_wave_scoreboard.sv" "input  logic [7:0]   matrix_accepted_a_base,"
Require-Literal "source/rtl/cgx1_matrix_wave_scoreboard.sv" "input  logic [7:0]   matrix_accepted_b_base,"
Require-Literal "source/rtl/cgx1_matrix_wave_scoreboard.sv" "input  logic [255:0] ordinary_read_mask,"
Require-Literal "source/rtl/cgx1_matrix_wave_scoreboard.sv" "output logic         ordinary_ready,"
Require-Literal "source/matrix/cgx1_matrix_result_staging.hpp" "struct MatrixResultStagingState"
Require-Literal "source/rtl/cgx1_matrix_result_staging.sv" "output logic [1023:0] rf_write_data"
Require-Literal "source/matrix/cgx1_matrix_int8_execution.hpp" "struct MatrixInt8ExecutionState"
Require-Literal "source/rtl/cgx1_matrix_int8_execution.sv" "module cgx1_matrix_int8_execution"
Require-Literal "source/matrix/cgx1_matrix_result_staging.hpp" "LoadAndConsumeMatrixResultCycleZero("
Require-Literal "source/rtl/cgx1_matrix_int8_path.sv" "module cgx1_matrix_int8_path"
Require-Literal "source/rtl/cgx1_matrix_int8_engine_shell.sv" "module cgx1_matrix_int8_engine_shell"
Require-Literal "source/rtl/cgx1_matrix_resident_wave_arbiter.sv" "module cgx1_matrix_resident_wave_arbiter"
Require-Literal "source/rtl/cgx1_matrix_resident_wave_scoreboard.sv" "module cgx1_matrix_resident_wave_scoreboard"
Require-Literal "source/rtl/cgx1_matrix_int8_resident_engine.sv" "module cgx1_matrix_int8_resident_engine"
Require-Literal "source/rtl/cgx1_resident_wave_vgpr_file.sv" "module cgx1_resident_wave_vgpr_file"
Require-Literal "source/rtl/cgx1_resident_wave_vgpr_file.sv" "logic [LANE_BITS-1:0] storage"
Require-Literal "source/rtl/cgx1_resident_wave_vgpr_file.sv" "[read_addr0[2:0]]"
Require-Literal "source/rtl/cgx1_resident_wave_vgpr_file.sv" "[read_addr0[7:3]]"
Require-Literal "source/rtl/cgx1_matrix_int8_engine_shell.sv" "localparam logic [3:0] INT8_OPCODE = 4'h6;"
Require-Literal "docs/MATRIX_ENGINE.md" "The architecture target is therefore one accepted matrix instruction per engine every **$matrixIssueInterval cycles**."
Require-Literal "source/power/cgx1_power_management.hpp" "kComputeTileCount = $($computeTiles)U;"
Require-Literal "source/power/cgx1_power_management.hpp" "P0SafeBoot:  return $($safeBoot).0;"
Require-Literal "source/power/cgx1_power_management.hpp" "P1SlotEco:   return $($slotEco).0;"
Require-Literal "source/power/cgx1_power_management.hpp" "P2SlotMax:   return $($slotMax).0;"
Require-Literal "source/power/cgx1_power_management.hpp" "P3DockQuiet: return $($dockQuiet).0;"
Require-Literal "source/power/cgx1_power_management.hpp" "P4DockFull:  return $($fullPower).0;"
Require-Literal "docs/POWER_MANAGEMENT.md" "0.55 V to 0.90 V"

Require-Literal "docs/THERMAL_POWER.md" "| **Total** | **$fullPower W** |"
Require-Literal "docs/MECHANICAL_DESIGN.md" ("The revised dock target is **$dockLength " + $multiply + " $dockWidth " + $multiply + " $dockHeight mm**.")
Require-Literal "docs/ELECTRICAL_INTERFACE.md" "returns directly to **P0 Safe Boot**"
Require-Literal "docs/STATUS.md" "$fp32 TFLOPS"
Require-Literal "docs/ENGINEERING_SPEC.md" "$l1Shared KB combined L1/shared memory per compute unit target."
Require-Literal "docs/ENGINEERING_SPEC.md" "$l2PerTile MB L2 slice per compute tile."
Require-Literal "docs/ENGINEERING_SPEC.md" "$l2Total MB aggregate L2 target."
Require-Literal "README.md" "| Package level cache target | $packageCache MB | Architecture target |"
Require-Literal "README.md" "| Power management | Per-tile DVFS/power gating policy inside unchanged P0-P4 board limits; no fixed tile count per P-state |"

if ([int]$architecture.schema_version -ne 20) {
    Add-Finding "design/cgx1_architecture.json: schema version must remain 20 for the pooled resident-wave VGPR RTL boundary"
}
if ($matrixScope -ne ("wave" + $wave)) {
    Add-Finding "design/cgx1_architecture.json: matrix cooperative scope must match native wave size"
}
if (-not [bool]$architecture.matrix_engine.physical_tile_dimensions_frozen) {
    Add-Finding "design/cgx1_architecture.json: physical matrix tile dimensions must remain frozen"
}
if (-not [bool]$architecture.matrix_engine.physical_fragment_mapping_frozen) {
    Add-Finding "design/cgx1_architecture.json: physical matrix fragment mapping must remain frozen"
}
if (-not [bool]$architecture.matrix_engine.throughput_frozen) {
    Add-Finding "design/cgx1_architecture.json: matrix throughput target must remain frozen"
}
if ([bool]$architecture.matrix_engine.independent_ai_tops_frozen) {
    Add-Finding "design/cgx1_architecture.json: independent AI TOPS must remain unfrozen"
}
if ([bool]$architecture.matrix_engine.structured_sparsity_acceleration_claimed) {
    Add-Finding "design/cgx1_architecture.json: structured sparsity acceleration must not be claimed in the baseline"
}
if (-not [bool]$architecture.matrix_engine.floating_reduction_order_frozen) {
    Add-Finding "design/cgx1_architecture.json: per-instruction floating matrix reduction order must remain frozen"
}
if (-not [bool]$architecture.matrix_engine.instruction_encoding_frozen) {
    Add-Finding "design/cgx1_architecture.json: matrix instruction encoding must remain frozen"
}
if ([bool]$architecture.matrix_engine.timing_feasibility_validated) {
    Add-Finding "design/cgx1_architecture.json: matrix timing feasibility must remain unvalidated until RTL timing evidence exists"
}
if ([bool]$architecture.matrix_engine.deterministic_matrix_mode_claimed) {
    Add-Finding "design/cgx1_architecture.json: deterministic matrix mode is not a baseline claim"
}
if ($matrixTileM -ne 16 -or $matrixTileN -ne 16 -or $matrixFp16K -ne 16 -or $matrixFp8K -ne 32) {
    Add-Finding "design/cgx1_architecture.json: matrix tile shapes must remain M16N16K16 for 16-bit inputs and M16N16K32 for 8-bit inputs"
}
if ($matrixSourceRegisters -ne 4 -or [int]$architecture.matrix_engine.fragment_registers_per_lane.source_b -ne 4 -or $matrixAccumulatorRegisters -ne 8) {
    Add-Finding "design/cgx1_architecture.json: matrix fragment register counts must remain 4/4/8 per lane"
}
if ($matrixCaptureCycles -ne 8 -or $matrixExecutionCycles -ne 16 -or $matrixWritebackCycles -ne 8) {
    Add-Finding "design/cgx1_architecture.json: matrix pipeline must remain 8 capture / 16 execute / 8 writeback cycles"
}
if ($matrixIssueInterval -ne 16) {
    Add-Finding "design/cgx1_architecture.json: matrix issue interval must remain 16 cycles"
}
if ($matrixResultLatency -ne 33) {
    Add-Finding "design/cgx1_architecture.json: matrix result latency must remain 33 cycles"
}
if ($matrixResultLatency -ne (1 + $matrixCaptureCycles + $matrixExecutionCycles + $matrixWritebackCycles)) {
    Add-Finding "design/cgx1_architecture.json: matrix result latency does not match the pipeline stages"
}

if ($matrixWaveRegisterReads -ne 2 -or $matrixWaveRegisterWrites -ne 1 -or $matrixWaveRegisterBits -ne 1024) {
    Add-Finding "design/cgx1_architecture.json: matrix VGPR interface must remain two 1024-bit reads or one 1024-bit write per active transfer cycle"
}
if ([bool]$architecture.matrix_engine.pipeline.simultaneous_matrix_read_write_required) {
    Add-Finding "design/cgx1_architecture.json: matrix schedule must not require simultaneous VGPR read and write access"
}
if ($matrixInputStageBytes -ne 2048 -or
    [int]$architecture.matrix_engine.staging_bytes.source_a -ne 512 -or
    [int]$architecture.matrix_engine.staging_bytes.source_b -ne 512 -or
    [int]$architecture.matrix_engine.staging_bytes.accumulator_result -ne 1024) {
    Add-Finding "design/cgx1_architecture.json: matrix input staging must remain 512/512/1024 bytes for A/B/C-D"
}

if ([int]$architecture.matrix_engine.fragment_register_alignment.source_a -ne 8 -or
    [int]$architecture.matrix_engine.fragment_register_alignment.source_b -ne 4 -or
    [int]$architecture.matrix_engine.fragment_register_alignment.accumulator_result -ne 8) {
    Add-Finding "design/cgx1_architecture.json: matrix register-group alignment must remain A=8, B=4, C-D=8"
}
if ($matrixBankClasses -ne 8 -or
    [string]$architecture.matrix_engine.register_banking.bank_select -ne "VGPR index modulo 8" -or
    $matrixSourceABankClass -ne 0 -or
    $matrixSourceBBankClass -ne 4 -or
    $matrixDestinationBankClass -ne 0) {
    Add-Finding "design/cgx1_architecture.json: matrix register bank classes must remain modulo-8 with A=0, B=4, C-D=0"
}
if (-not [bool]$architecture.matrix_engine.register_banking.source_b_exact_alias_of_a_allowed) {
    Add-Finding "design/cgx1_architecture.json: exact A-B source alias broadcast must remain allowed"
}
if (-not [bool]$architecture.matrix_engine.register_banking.single_matrix_access_per_bank_class_per_cycle) {
    Add-Finding "design/cgx1_architecture.json: matrix banking contract requires one matrix access per bank class per cycle"
}
if ([bool]$architecture.matrix_engine.register_banking.physical_wave_storage_depth_frozen) {
    Add-Finding "design/cgx1_architecture.json: physical VGPR bank storage depth must remain unfrozen"
}

if (-not [bool]$architecture.matrix_engine.matrix_to_matrix_dependencies.pending_destination_raw_interlock) {
    Add-Finding "design/cgx1_architecture.json: matrix RAW interlock against pending destinations must remain enabled"
}
if (-not [bool]$architecture.matrix_engine.matrix_to_matrix_dependencies.pending_destination_waw_interlock) {
    Add-Finding "design/cgx1_architecture.json: matrix WAW interlock against pending destinations must remain enabled"
}
if ([bool]$architecture.matrix_engine.matrix_to_matrix_dependencies.matrix_to_matrix_war_possible_at_minimum_issue_interval) {
    Add-Finding "design/cgx1_architecture.json: matrix-to-matrix WAR must remain impossible at the frozen minimum issue interval"
}
if ([bool]$architecture.matrix_engine.matrix_to_matrix_dependencies.general_compute_unit_scoreboard_integrated) {
    Add-Finding "design/cgx1_architecture.json: general compute-unit scoreboard integration must remain unclaimed"
}
if (-not [bool]$architecture.matrix_engine.matrix_to_matrix_dependencies.ordinary_vector_source_write_interlock_implemented) {
    Add-Finding "design/cgx1_architecture.json: ordinary vector WAR interlock logic must remain implemented"
}
if (-not [bool]$architecture.matrix_engine.matrix_to_matrix_dependencies.ordinary_vector_pending_destination_read_interlock_implemented) {
    Add-Finding "design/cgx1_architecture.json: ordinary vector RAW interlock logic must remain implemented"
}
if (-not [bool]$architecture.matrix_engine.matrix_to_matrix_dependencies.ordinary_vector_pending_destination_write_interlock_implemented) {
    Add-Finding "design/cgx1_architecture.json: ordinary vector WAW interlock logic must remain implemented"
}

if ([string]$architecture.matrix_engine.wave_vgpr_scoreboard.scope -ne "one wave context" -or
    [int]$architecture.matrix_engine.wave_vgpr_scoreboard.register_count -ne 256) {
    Add-Finding "design/cgx1_architecture.json: matrix per-wave scoreboard scope must remain one 256-VGPR wave context"
}
if (-not [bool]$architecture.matrix_engine.wave_vgpr_scoreboard.tracks_matrix_source_reservations -or
    -not [bool]$architecture.matrix_engine.wave_vgpr_scoreboard.tracks_matrix_destination_reservations -or
    -not [bool]$architecture.matrix_engine.wave_vgpr_scoreboard.ordinary_raw_check -or
    -not [bool]$architecture.matrix_engine.wave_vgpr_scoreboard.ordinary_waw_check -or
    -not [bool]$architecture.matrix_engine.wave_vgpr_scoreboard.ordinary_war_check -or
    -not [bool]$architecture.matrix_engine.wave_vgpr_scoreboard.capture_read_port_conflict_check -or
    -not [bool]$architecture.matrix_engine.wave_vgpr_scoreboard.writeback_write_port_conflict_check) {
    Add-Finding "design/cgx1_architecture.json: matrix per-wave scoreboard hazard coverage is incomplete"
}
if (-not [bool]$architecture.matrix_engine.wave_vgpr_scoreboard.same_cycle_matrix_reservation_visible_to_ordinary_issue -or
    -not [bool]$architecture.matrix_engine.wave_vgpr_scoreboard.reference_model_implemented -or
    -not [bool]$architecture.matrix_engine.wave_vgpr_scoreboard.rtl_implemented -or
    -not [bool]$architecture.matrix_engine.wave_vgpr_scoreboard.simulation_exercised) {
    Add-Finding "design/cgx1_architecture.json: matrix per-wave scoreboard implementation status is incomplete"
}

if (-not [bool]$architecture.matrix_engine.pipeline_control_rtl.accepted_register_bases_exposed -or
    -not [bool]$architecture.matrix_engine.wave_vgpr_scoreboard.accepted_register_bases_latched_by_pipeline_control -or
    [string]$architecture.matrix_engine.wave_vgpr_scoreboard.reservation_event_source -ne "registered issue acceptance with controller-latched D/A/B bases") {
    Add-Finding "design/cgx1_architecture.json: matrix scoreboard reservation must use controller-latched accepted register bases"
}
if (-not [bool]$architecture.matrix_engine.wave_vgpr_scoreboard.ordinary_issue_admission_integrated -or
    -not [bool]$architecture.matrix_engine.wave_vgpr_scoreboard.resident_wave_identity_integrated -or
    -not [bool]$architecture.matrix_engine.wave_vgpr_scoreboard.resident_wave_router_rtl_implemented) {
    Add-Finding "design/cgx1_architecture.json: resident-wave matrix scoreboard routing/admission contract is incomplete"
}
if ([bool]$architecture.matrix_engine.wave_vgpr_scoreboard.ordinary_issue_pipeline_integrated -or
    [bool]$architecture.matrix_engine.wave_vgpr_scoreboard.multi_wave_storage_organization_frozen -or
    [bool]$architecture.matrix_engine.wave_vgpr_scoreboard.resident_wave_slot_count_frozen) {
    Add-Finding "design/cgx1_architecture.json: resident-wave scoreboard must not claim unfinished physical CU integration"
}
if (-not [bool]$architecture.matrix_engine.wave_vgpr_scoreboard.resident_wave_router_simulation_exercised) {
    Add-Finding "design/cgx1_architecture.json: resident-wave scoreboard simulation evidence must remain true after exact-revision RTL CI passes"
}
if (-not [bool]$architecture.matrix_engine.pipeline_control_rtl.implemented -or
    -not [bool]$architecture.matrix_engine.pipeline_control_rtl.simulation_exercised -or
    -not [bool]$architecture.matrix_engine.pipeline_control_rtl.operand_staging_rtl_implemented -or
    -not [bool]$architecture.matrix_engine.pipeline_control_rtl.output_result_staging_rtl_implemented -or
    -not [bool]$architecture.matrix_engine.pipeline_control_rtl.writeback_cycle_index_exposed -or
    -not [bool]$architecture.matrix_engine.pipeline_control_rtl.resident_wave_identity_simulation_exercised) {
    Add-Finding "design/cgx1_architecture.json: matrix control/staging RTL implementation and simulation status must remain enabled"
}
if ([bool]$architecture.matrix_engine.pipeline_control_rtl.arithmetic_datapath_implemented -or
    [bool]$architecture.matrix_engine.pipeline_control_rtl.physical_vgpr_storage_implemented -or
    [bool]$architecture.matrix_engine.pipeline_control_rtl.physical_staging_storage_validated -or
    [bool]$architecture.matrix_engine.pipeline_control_rtl.cross_lane_data_path_implemented -or
    [bool]$architecture.matrix_engine.pipeline_control_rtl.timing_closure_validated) {
    Add-Finding "design/cgx1_architecture.json: matrix control/staging RTL must not claim unfinished datapath or physical implementation work"
}

if ([int]$architecture.matrix_engine.staging_storage.capture_buffer_bytes -ne 2048 -or
    $matrixActiveExecutionBytes -ne 2048 -or
    $matrixOutputStageBytes -ne 1024 -or
    $matrixLogicalStoragePerEngine -ne 5120 -or
    $matrixLogicalStoragePerCu -ne 20480) {
    Add-Finding "design/cgx1_architecture.json: matrix logical staging storage must remain 2048/2048/1024 bytes and 5120 bytes per engine"
}
if ($matrixLogicalStoragePerCu -ne ($matrixLogicalStoragePerEngine * $matrixEnginesPerCu)) {
    Add-Finding "design/cgx1_architecture.json: matrix logical staging storage per CU does not match per-engine storage times engine count"
}
if ([int]$architecture.matrix_engine.staging_storage.active_commit_capture_cycle -ne 7 -or
    -not [bool]$architecture.matrix_engine.staging_storage.capture_cycle_index_exposed_by_control_rtl -or
    -not [bool]$architecture.matrix_engine.staging_storage.capture_buffer_rtl_implemented -or
    -not [bool]$architecture.matrix_engine.staging_storage.active_execution_operand_rtl_implemented) {
    Add-Finding "design/cgx1_architecture.json: matrix capture-to-active staging RTL contract is incomplete"
}
if (-not [bool]$architecture.matrix_engine.staging_storage.output_result_staging_rtl_implemented) {
    Add-Finding "design/cgx1_architecture.json: matrix output-result staging RTL must remain implemented"
}
if (-not [bool]$architecture.matrix_engine.staging_storage.result_writeback_order_enforced -or
    -not [bool]$architecture.matrix_engine.staging_storage.result_slot_overwrite_rejected -or
    [int]$architecture.matrix_engine.staging_storage.result_slot_release_writeback_cycle -ne 7 -or
    -not [bool]$architecture.matrix_engine.staging_storage.writeback_cycle_index_exposed_by_control_rtl) {
    Add-Finding "design/cgx1_architecture.json: matrix output-result staging order/release contract is incomplete"
}
if (-not [bool]$architecture.matrix_engine.staging_storage.result_source_arithmetic_datapath_integrated -or
    -not [bool]$architecture.matrix_engine.staging_storage.result_cycle0_load_to_writeback_bypass -or
    -not [bool]$architecture.matrix_engine.staging_storage.result_cycle0_bypass_reference_model -or
    -not [bool]$architecture.matrix_engine.staging_storage.result_cycle0_bypass_rtl_implemented) {
    Add-Finding "design/cgx1_architecture.json: matrix INT8 result-source and cycle-0 bypass integration is incomplete"
}
if (-not [bool]$architecture.matrix_engine.staging_storage.result_cycle0_bypass_simulation_exercised) {
    Add-Finding "design/cgx1_architecture.json: cycle-0 result bypass simulation evidence must remain recorded"
}
if ([bool]$architecture.matrix_engine.staging_storage.physical_macro_selection_frozen) {
    Add-Finding "design/cgx1_architecture.json: matrix physical storage macro must remain unclaimed"
}

if (-not [bool]$architecture.matrix_engine.pipeline_control_rtl.execute_cycle_index_exposed -or
    -not [bool]$architecture.matrix_engine.pipeline_control_rtl.execute_opcode_exposed) {
    Add-Finding "design/cgx1_architecture.json: matrix execute-cycle index and opcode must remain exposed by control RTL"
}
if (-not [bool]$architecture.matrix_engine.arithmetic_rtl.int8_m16n16k32_implemented -or
    -not [bool]$architecture.matrix_engine.arithmetic_rtl.int8_two_k_terms_per_cycle -or
    [int]$architecture.matrix_engine.arithmetic_rtl.int8_execution_cycles -ne 16 -or
    -not [bool]$architecture.matrix_engine.arithmetic_rtl.canonical_fragment_mapping_used -or
    -not [bool]$architecture.matrix_engine.arithmetic_rtl.reference_model_implemented -or
    -not [bool]$architecture.matrix_engine.arithmetic_rtl.rtl_implemented -or
    -not [bool]$architecture.matrix_engine.arithmetic_rtl.rtl_testbench_implemented) {
    Add-Finding "design/cgx1_architecture.json: signed INT8 matrix arithmetic implementation contract is incomplete"
}
if ([string]$architecture.matrix_engine.arithmetic_rtl.int8_accumulation -ne "two signed INT32 modulo-2^32 chains with even K initialized from C and odd K initialized from zero; final modulo-2^32 combine") {
    Add-Finding "design/cgx1_architecture.json: signed INT8 matrix accumulation contract changed"
}
if ([string]$architecture.matrix_engine.arithmetic_rtl.result_word_format -ne "eight whole-wave signed INT32 result registers") {
    Add-Finding "design/cgx1_architecture.json: signed INT8 matrix result format changed"
}
if (-not [bool]$architecture.matrix_engine.arithmetic_rtl.simulation_exercised) {
    Add-Finding "design/cgx1_architecture.json: standalone signed INT8 RTL simulation evidence must remain recorded"
}
if ([bool]$architecture.matrix_engine.arithmetic_rtl.fp16_rtl_implemented -or
    [bool]$architecture.matrix_engine.arithmetic_rtl.bf16_rtl_implemented -or
    [bool]$architecture.matrix_engine.arithmetic_rtl.fp8_rtl_implemented) {
    Add-Finding "design/cgx1_architecture.json: floating matrix arithmetic must remain unimplemented until FP32-FMA RTL exists"
}
if ([bool]$architecture.matrix_engine.arithmetic_rtl.timing_closure_validated -or
    [bool]$architecture.matrix_engine.arithmetic_rtl.area_validated -or
    [bool]$architecture.matrix_engine.arithmetic_rtl.power_validated) {
    Add-Finding "design/cgx1_architecture.json: INT8 arithmetic physical implementation evidence must remain unclaimed"
}

if (-not [bool]$architecture.matrix_engine.int8_path_integration.implemented -or
    -not [bool]$architecture.matrix_engine.int8_path_integration.controller_capture_cycle_used -or
    -not [bool]$architecture.matrix_engine.int8_path_integration.controller_execute_cycle_used -or
    -not [bool]$architecture.matrix_engine.int8_path_integration.controller_execute_opcode_used -or
    -not [bool]$architecture.matrix_engine.int8_path_integration.controller_writeback_cycle_used -or
    -not [bool]$architecture.matrix_engine.int8_path_integration.operand_staging_connected -or
    -not [bool]$architecture.matrix_engine.int8_path_integration.arithmetic_connected -or
    -not [bool]$architecture.matrix_engine.int8_path_integration.result_staging_connected -or
    -not [bool]$architecture.matrix_engine.int8_path_integration.cycle0_result_bypass_required -or
    -not [bool]$architecture.matrix_engine.int8_path_integration.rtl_testbench_implemented) {
    Add-Finding "design/cgx1_architecture.json: integrated signed INT8 path contract is incomplete"
}
if (-not [bool]$architecture.matrix_engine.int8_path_integration.simulation_exercised) {
    Add-Finding "design/cgx1_architecture.json: integrated INT8 path simulation evidence must remain recorded"
}
if ([bool]$architecture.matrix_engine.int8_path_integration.physical_timing_validated -or
    [bool]$architecture.matrix_engine.int8_path_integration.physical_area_validated -or
    [bool]$architecture.matrix_engine.int8_path_integration.physical_power_validated) {
    Add-Finding "design/cgx1_architecture.json: integrated INT8 path physical evidence must remain unclaimed"
}

if (-not [bool]$architecture.matrix_engine.int8_engine_shell.implemented -or
    [string]$architecture.matrix_engine.int8_engine_shell.supported_matrix_opcode -ne "0x6" -or
    -not [bool]$architecture.matrix_engine.int8_engine_shell.single_wave_context -or
    -not [bool]$architecture.matrix_engine.int8_engine_shell.pipeline_control_connected -or
    -not [bool]$architecture.matrix_engine.int8_engine_shell.per_wave_scoreboard_connected -or
    -not [bool]$architecture.matrix_engine.int8_engine_shell.int8_path_connected -or
    -not [bool]$architecture.matrix_engine.int8_engine_shell.external_vgpr_read_interface -or
    -not [bool]$architecture.matrix_engine.int8_engine_shell.external_vgpr_write_interface -or
    -not [bool]$architecture.matrix_engine.int8_engine_shell.ordinary_hazard_interface -or
    -not [bool]$architecture.matrix_engine.int8_engine_shell.rejects_non_int8_matrix_opcodes -or
    -not [bool]$architecture.matrix_engine.int8_engine_shell.rtl_testbench_implemented) {
    Add-Finding "design/cgx1_architecture.json: single-engine INT8 shell contract is incomplete"
}
if (-not [bool]$architecture.matrix_engine.int8_engine_shell.simulation_exercised) {
    Add-Finding "design/cgx1_architecture.json: INT8 shell simulation evidence must remain recorded"
}
if ([bool]$architecture.matrix_engine.int8_engine_shell.physical_vgpr_file_implemented -or
    [bool]$architecture.matrix_engine.int8_engine_shell.resident_wave_arbitration_integrated -or
    [bool]$architecture.matrix_engine.int8_engine_shell.ordinary_vector_issue_pipeline_integrated -or
    [bool]$architecture.matrix_engine.int8_engine_shell.floating_matrix_opcodes_supported) {
    Add-Finding "design/cgx1_architecture.json: INT8 shell must not claim unfinished CU or floating-matrix integration"
}
if ([bool]$architecture.matrix_engine.int8_engine_shell.timing_closure_validated -or
    [bool]$architecture.matrix_engine.int8_engine_shell.area_validated -or
    [bool]$architecture.matrix_engine.int8_engine_shell.power_validated) {
    Add-Finding "design/cgx1_architecture.json: INT8 shell physical implementation evidence must remain unclaimed"
}

if (-not [bool]$architecture.matrix_engine.int8_resident_engine.implemented -or
    [string]$architecture.matrix_engine.int8_resident_engine.supported_matrix_opcode -ne "0x6" -or
    -not [bool]$architecture.matrix_engine.int8_resident_engine.resident_wave_slot_count_parameterized -or
    [bool]$architecture.matrix_engine.int8_resident_engine.resident_wave_slot_count_frozen -or
    -not [bool]$architecture.matrix_engine.int8_resident_engine.round_robin_matrix_request_arbiter -or
    -not [bool]$architecture.matrix_engine.int8_resident_engine.wave_identity_propagated_through_pipeline -or
    -not [bool]$architecture.matrix_engine.int8_resident_engine.wave_local_matrix_dependency_interlocks -or
    -not [bool]$architecture.matrix_engine.int8_resident_engine.wave_tagged_external_vgpr_interface -or
    -not [bool]$architecture.matrix_engine.int8_resident_engine.per_wave_scoreboard_routing -or
    -not [bool]$architecture.matrix_engine.int8_resident_engine.ordinary_issue_admission_handshake -or
    -not [bool]$architecture.matrix_engine.int8_resident_engine.rtl_testbench_implemented) {
    Add-Finding "design/cgx1_architecture.json: resident-wave INT8 engine contract is incomplete"
}
if (-not [bool]$architecture.matrix_engine.int8_resident_engine.simulation_exercised) {
    Add-Finding "design/cgx1_architecture.json: resident-wave INT8 simulation evidence must remain true after exact-revision RTL CI passes"
}
if ([bool]$architecture.matrix_engine.int8_resident_engine.ordinary_vector_execution_datapath_integrated -or
    [bool]$architecture.matrix_engine.int8_resident_engine.physical_vgpr_file_implemented -or
    [bool]$architecture.matrix_engine.int8_resident_engine.floating_matrix_opcodes_supported -or
    [bool]$architecture.matrix_engine.int8_resident_engine.timing_closure_validated -or
    [bool]$architecture.matrix_engine.int8_resident_engine.area_validated -or
    [bool]$architecture.matrix_engine.int8_resident_engine.power_validated) {
    Add-Finding "design/cgx1_architecture.json: resident-wave INT8 boundary must not claim unfinished physical or floating integration"
}

if (-not [bool]$architecture.matrix_engine.vgpr_storage_rtl.implemented -or
    -not [bool]$architecture.matrix_engine.vgpr_storage_rtl.resident_wave_slot_count_parameterized -or
    [bool]$architecture.matrix_engine.vgpr_storage_rtl.resident_wave_slot_count_frozen -or
    [int]$architecture.matrix_engine.vgpr_storage_rtl.architectural_registers_per_wave -ne 256 -or
    [int]$architecture.matrix_engine.vgpr_storage_rtl.wave_lanes -ne 32 -or
    [int]$architecture.matrix_engine.vgpr_storage_rtl.lane_word_bits -ne 32 -or
    [int]$architecture.matrix_engine.vgpr_storage_rtl.wave_register_width_bits -ne 1024 -or
    [int]$architecture.matrix_engine.vgpr_storage_rtl.bank_classes -ne 8 -or
    [int]$architecture.matrix_engine.vgpr_storage_rtl.rows_per_bank -ne 32 -or
    [int]$architecture.matrix_engine.vgpr_storage_rtl.read_ports -ne 2 -or
    [int]$architecture.matrix_engine.vgpr_storage_rtl.write_ports -ne 1 -or
    -not [bool]$architecture.matrix_engine.vgpr_storage_rtl.exact_alias_broadcast -or
    -not [bool]$architecture.matrix_engine.vgpr_storage_rtl.fixed_lane_order_delivery -or
    -not [bool]$architecture.matrix_engine.vgpr_storage_rtl.rtl_testbench_implemented) {
    Add-Finding "design/cgx1_architecture.json: resident-wave VGPR storage RTL contract is incomplete"
}
if (-not [bool]$architecture.matrix_engine.vgpr_storage_rtl.simulation_exercised) {
    Add-Finding "design/cgx1_architecture.json: resident-wave VGPR storage simulation evidence must remain recorded after its exact-revision RTL CI pass"
}
if ([bool]$architecture.matrix_engine.vgpr_storage_rtl.physical_macro_selected -or
    [bool]$architecture.matrix_engine.vgpr_storage_rtl.timing_closure_validated -or
    [bool]$architecture.matrix_engine.vgpr_storage_rtl.area_validated -or
    [bool]$architecture.matrix_engine.vgpr_storage_rtl.power_validated) {
    Add-Finding "design/cgx1_architecture.json: VGPR storage RTL must not claim foundry macro, timing, area, or power validation"
}


Require-Literal "source/rtl/cgx1_pooled_vgpr_mapper.sv" "module cgx1_pooled_vgpr_mapper"
Require-Literal "source/rtl/cgx1_resident_wave_vgpr_allocator.sv" "module cgx1_resident_wave_vgpr_allocator"
Require-Literal "source/rtl/cgx1_pooled_vgpr_storage.sv" "module cgx1_pooled_vgpr_storage"
Require-Literal "source/rtl/cgx1_matrix_request_preflight_array.sv" "module cgx1_matrix_request_preflight_array"
Require-Literal "source/rtl/cgx1_pooled_vgpr_matrix_subsystem.sv" "module cgx1_pooled_vgpr_matrix_subsystem"
Require-Literal "source/rtl/cgx1_matrix_int8_pooled_resident_engine.sv" "module cgx1_matrix_int8_pooled_resident_engine"

if (-not [bool]$architecture.matrix_engine.pooled_vgpr_rtl.implemented -or
    -not [bool]$architecture.matrix_engine.pooled_vgpr_rtl.exact_register_count_enforced -or
    [int]$architecture.matrix_engine.pooled_vgpr_rtl.physical_row_register_granularity -ne 8 -or
    [int]$architecture.matrix_engine.pooled_vgpr_rtl.bank_classes -ne 8 -or
    -not [bool]$architecture.matrix_engine.pooled_vgpr_rtl.resident_wave_slot_count_parameterized -or
    [bool]$architecture.matrix_engine.pooled_vgpr_rtl.resident_wave_slot_count_frozen -or
    -not [bool]$architecture.matrix_engine.pooled_vgpr_rtl.physical_row_capacity_parameterized -or
    [bool]$architecture.matrix_engine.pooled_vgpr_rtl.physical_row_capacity_frozen -or
    -not [bool]$architecture.matrix_engine.pooled_vgpr_rtl.serialized_validity_invalidation -or
    -not [bool]$architecture.matrix_engine.pooled_vgpr_rtl.round_robin_invalidation_selection -or
    -not [bool]$architecture.matrix_engine.pooled_vgpr_rtl.privileged_reserved_restore -or
    -not [bool]$architecture.matrix_engine.pooled_vgpr_rtl.active_release_requires_quiescence -or
    -not [bool]$architecture.matrix_engine.pooled_vgpr_rtl.resident_matrix_busy_blocks_release -or
    -not [bool]$architecture.matrix_engine.pooled_vgpr_rtl.same_wave_restore_blocks_activation -or
    -not [bool]$architecture.matrix_engine.pooled_vgpr_rtl.runtime_preflight_preserves_controller_illegal_authority -or
    -not [bool]$architecture.matrix_engine.pooled_vgpr_rtl.matrix_capture_connected -or
    -not [bool]$architecture.matrix_engine.pooled_vgpr_rtl.matrix_writeback_connected -or
    -not [bool]$architecture.matrix_engine.pooled_vgpr_rtl.resident_int8_engine_connected -or
    -not [bool]$architecture.matrix_engine.pooled_vgpr_rtl.rtl_testbenches_implemented) {
    Add-Finding "design/cgx1_architecture.json: pooled resident-wave VGPR RTL contract is incomplete"
}
if ([bool]$architecture.matrix_engine.pooled_vgpr_rtl.simulation_exercised) {
    Add-Finding "design/cgx1_architecture.json: pooled resident-wave VGPR simulation evidence must remain false until the exact published revision passes RTL CI"
}
if ([bool]$architecture.matrix_engine.pooled_vgpr_rtl.ordinary_vector_execution_datapath_integrated -or
    [bool]$architecture.matrix_engine.pooled_vgpr_rtl.physical_macro_selected -or
    [bool]$architecture.matrix_engine.pooled_vgpr_rtl.timing_closure_validated -or
    [bool]$architecture.matrix_engine.pooled_vgpr_rtl.area_validated -or
    [bool]$architecture.matrix_engine.pooled_vgpr_rtl.power_validated) {
    Add-Finding "design/cgx1_architecture.json: pooled VGPR RTL must not claim unfinished vector or physical implementation evidence"
}

$matrixEngineCount = [double]$architecture.silicon.compute_units_total * [double]$architecture.silicon.matrix_engines_per_compute_unit
$matrixPeakClock = [double]$architecture.silicon.peak_clock_ghz
$matrixSustainedClock = [double]$architecture.silicon.sustained_clock_target_ghz
$fp16OpsPerInstruction = 2.0 * $matrixTileM * $matrixTileN * $matrixFp16K
$fp8OpsPerInstruction = 2.0 * $matrixTileM * $matrixTileN * $matrixFp8K
$expectedFp16Peak = ($fp16OpsPerInstruction / $matrixIssueInterval) * $matrixEngineCount * $matrixPeakClock / 1000.0
$expectedFp16Sustained = ($fp16OpsPerInstruction / $matrixIssueInterval) * $matrixEngineCount * $matrixSustainedClock / 1000.0
$expectedFp8Peak = ($fp8OpsPerInstruction / $matrixIssueInterval) * $matrixEngineCount * $matrixPeakClock / 1000.0
$expectedFp8Sustained = ($fp8OpsPerInstruction / $matrixIssueInterval) * $matrixEngineCount * $matrixSustainedClock / 1000.0

if ([Math]::Abs(([double]$architecture.matrix_engine.dense_rate_targets.fp16_bf16_peak_clock_tflops) - $expectedFp16Peak) -gt 0.0001 -or
    [Math]::Abs(([double]$architecture.matrix_engine.dense_rate_targets.fp16_bf16_sustained_clock_tflops) - $expectedFp16Sustained) -gt 0.0001) {
    Add-Finding "design/cgx1_architecture.json: FP16/BF16 dense matrix rate targets do not match the frozen issue model"
}
if ([Math]::Abs(([double]$architecture.matrix_engine.dense_rate_targets.fp8_peak_clock_tflops) - $expectedFp8Peak) -gt 0.0001 -or
    [Math]::Abs(([double]$architecture.matrix_engine.dense_rate_targets.fp8_sustained_clock_tflops) - $expectedFp8Sustained) -gt 0.0001 -or
    [Math]::Abs(([double]$architecture.matrix_engine.dense_rate_targets.int8_peak_clock_tops) - $expectedFp8Peak) -gt 0.0001 -or
    [Math]::Abs(([double]$architecture.matrix_engine.dense_rate_targets.int8_sustained_clock_tops) - $expectedFp8Sustained) -gt 0.0001) {
    Add-Finding "design/cgx1_architecture.json: FP8/INT8 dense matrix rate targets do not match the frozen issue model"
}
if ([bool]$architecture.matrix_engine.fp32_input_matrix_baseline -or [bool]$architecture.matrix_engine.fp64_matrix_baseline -or [bool]$architecture.matrix_engine.tf32_baseline -or [bool]$architecture.matrix_engine.ocp_mx_baseline) {
    Add-Finding "design/cgx1_architecture.json: non-baseline matrix formats were enabled without a frozen contract"
}
if (-not [bool]$architecture.matrix_engine.capability_discovery_required) {
    Add-Finding "design/cgx1_architecture.json: matrix capability discovery is required"
}
if ([string]$architecture.matrix_engine.fp8_standard -ne "OCP OFP8 Revision 1.0") {
    Add-Finding "design/cgx1_architecture.json: FP8 standard does not match the matrix numeric contract"
}
$fp8SaturationModes = @($architecture.matrix_engine.fp8_saturation_modes)
if ($fp8SaturationModes.Count -ne 2 -or $fp8SaturationModes -notcontains "saturating" -or $fp8SaturationModes -notcontains "non-saturating") {
    Add-Finding "design/cgx1_architecture.json: FP8 saturation modes must match the OCP OFP8 contract"
}
if ([string]$architecture.matrix_engine.floating_operand_widening -ne "exact to FP32 before accumulation") {
    Add-Finding "design/cgx1_architecture.json: floating matrix operands must widen exactly to FP32"
}
if ([string]$architecture.matrix_engine.floating_accumulation_step -ne "FP32 fused multiply-add") {
    Add-Finding "design/cgx1_architecture.json: floating matrix accumulation step must use FP32 fused multiply-add semantics"
}
if ([bool]$architecture.power_management.full_hbm_availability_in_p0_claimed) {
    Add-Finding "design/cgx1_architecture.json: full HBM availability must not be claimed in P0 before characterization"
}
if (-not [bool]$architecture.power_management.hysteresis_required) {
    Add-Finding "design/cgx1_architecture.json: power-management hysteresis is required"
}
if ([bool]$architecture.power_management.hysteresis_timing_frozen) {
    Add-Finding "design/cgx1_architecture.json: hysteresis timing must remain unfrozen until characterization"
}
if (-not [bool]$architecture.power_management.emergency_isolation_may_bypass_orderly_drain) {
    Add-Finding "design/cgx1_architecture.json: emergency isolation must retain authority over orderly drain"
}
if ([bool]$architecture.power_management.emergency_isolation_preserves_unfinished_work) {
    Add-Finding "design/cgx1_architecture.json: unfinished work must not be claimed preserved across emergency isolation"
}
if ([bool]$architecture.power_management.tile_states.T0.scheduler_eligible -or
    [bool]$architecture.power_management.tile_states.T1.scheduler_eligible -or
    [bool]$architecture.power_management.tile_states.T2.scheduler_eligible -or
    -not [bool]$architecture.power_management.tile_states.T3.scheduler_eligible -or
    -not [bool]$architecture.power_management.tile_states.T4.scheduler_eligible -or
    -not [bool]$architecture.power_management.tile_states.T5.scheduler_eligible) {
    Add-Finding "design/cgx1_architecture.json: tile scheduler eligibility does not match the power-management contract"
}
if ([bool]$architecture.power_management.fixed_active_tile_count_by_board_state) {
    Add-Finding "design/cgx1_architecture.json: board states must not encode a fixed active tile count"
}
if ([bool]$architecture.power_management.vf_curve_frozen) {
    Add-Finding "design/cgx1_architecture.json: V/F curve must remain unfrozen until characterization"
}
if (-not [bool]$architecture.power_management.independent_tile_dvfs_target) {
    Add-Finding "design/cgx1_architecture.json: independent per-tile DVFS target is required"
}
if ($p0TileCap -ne "T2" -or $p1TileCap -ne "T3" -or $p2TileCap -ne "T4" -or $p3TileCap -ne "T5" -or $p4TileCap -ne "T5") {
    Add-Finding "design/cgx1_architecture.json: board-state tile caps do not match the power-management contract"
}
if ($pmVoltageMin -ne "0.55" -or $pmVoltageMax -ne "0.90") {
    Add-Finding "design/cgx1_architecture.json: power-management voltage target range does not match the engineering specification"
}
if (([int]$architecture.cache.l2_mb_per_tile * [int]$architecture.silicon.compute_tiles) -ne [int]$architecture.cache.l2_total_mb) {
    Add-Finding "design/cgx1_architecture.json: L2 total does not match per-tile cache capacity"
}
if (([int]$architecture.execution_model.simd_partitions_per_compute_unit * [int]$architecture.execution_model.lanes_per_simd_partition) -ne [int]$architecture.silicon.fp32_lanes_per_compute_unit) {
    Add-Finding "design/cgx1_architecture.json: SIMD partition product must equal FP32 lanes per compute unit"
}
if (([int]$architecture.texture_subsystem.texture_blocks_per_tile * [int]$architecture.silicon.compute_tiles) -ne [int]$architecture.texture_subsystem.texture_blocks_total) {
    Add-Finding "design/cgx1_architecture.json: texture block total does not match per-tile count"
}
if (([int]$architecture.graphics_pipeline.rop_lanes_per_tile * [int]$architecture.silicon.compute_tiles) -ne [int]$architecture.silicon.rop_target) {
    Add-Finding "design/cgx1_architecture.json: ROP lane total does not match silicon ROP target"
}
if ([double]$architecture.chiplet_fabric.aggregate_read_payload_target_tbps -lt [double]$architecture.memory.peak_bandwidth_tbps) {
    Add-Finding "design/cgx1_architecture.json: fabric read target is below HBM4 peak bandwidth target"
}
if ($dockFallback -ne $safeBoot) {
    Add-Finding "design/cgx1_architecture.json: dock fault fallback must equal Safe Boot power"
}


Require-Literal "source/rtl/cgx1_pooled_vgpr_execution_subsystem.sv" "module cgx1_pooled_vgpr_execution_subsystem"
Require-Literal "source/rtl/cgx1_vector_int32_alu.sv" "module cgx1_vector_int32_alu"
Require-Literal "source/rtl/cgx1_vector_int32_pipeline.sv" "module cgx1_vector_int32_pipeline"
Require-Literal "source/rtl/cgx1_vector_resident_wave_scheduler.sv" "module cgx1_vector_resident_wave_scheduler"
Require-Literal "source/rtl/cgx1_matrix_vector_hazard_guard.sv" "module cgx1_matrix_vector_hazard_guard"
Require-Literal "source/rtl/cgx1_matrix_vector_issue_arbiter.sv" "module cgx1_matrix_vector_issue_arbiter"

$vectorRtl = $architecture.execution_model.ordinary_vector_rtl
if (-not [bool]$vectorRtl.implemented -or
    [int]$vectorRtl.lane_count -ne 32 -or
    [int]$vectorRtl.element_bits -ne 32 -or
    [int]$vectorRtl.internal_opcode_width_bits -ne 4 -or
    [bool]$vectorRtl.internal_opcode_encoding_frozen -or
    -not [bool]$vectorRtl.read_execute_writeback_pipeline -or
    -not [bool]$vectorRtl.same_bank_two_source_serialization -or
    -not [bool]$vectorRtl.resident_wave_slot_count_parameterized -or
    -not [bool]$vectorRtl.resident_wave_slot_width_guard -or
    -not [bool]$vectorRtl.pooled_vgpr_shared_storage_integrated -or
    -not [bool]$vectorRtl.matrix_fixed_cycle_port_priority -or
    -not [bool]$vectorRtl.ordinary_restore_bounded_fairness -or
    -not [bool]$vectorRtl.matrix_vector_hazard_guard_implemented -or
    -not [bool]$vectorRtl.same_cycle_matrix_vector_acceptance_prevented -or
    -not [bool]$vectorRtl.unified_matrix_vector_restore_subsystem -or
    -not [bool]$vectorRtl.rtl_testbenches_implemented) {
    Add-Finding "design/cgx1_architecture.json: ordinary vector RTL contract is incomplete"
}
if ([bool]$vectorRtl.simulation_exercised) {
    Add-Finding "design/cgx1_architecture.json: ordinary vector RTL simulation evidence must remain false until exact-revision RTL CI passes"
}
if ([bool]$vectorRtl.timing_closure_validated -or
    [bool]$vectorRtl.area_validated -or
    [bool]$vectorRtl.power_validated) {
    Add-Finding "design/cgx1_architecture.json: ordinary vector RTL must not claim unfinished physical evidence"
}


Require-Literal "source/rtl/cgx1_compute_int8_vector_execution_frontend.sv" "module cgx1_compute_int8_vector_execution_frontend"

$mixedFrontend = $architecture.execution_model.mixed_matrix_vector_frontend_rtl
if (-not [bool]$mixedFrontend.implemented -or
    -not [bool]$mixedFrontend.one_shared_pooled_vgpr_authority -or
    -not [bool]$mixedFrontend.matrix_controller_illegal_authority_preserved -or
    -not [bool]$mixedFrontend.legal_matrix_runtime_preflight_required -or
    -not [bool]$mixedFrontend.live_vector_locks_gate_matrix_issue -or
    -not [bool]$mixedFrontend.matrix_scoreboard_gates_selected_vector_issue -or
    -not [bool]$mixedFrontend.same_cycle_matrix_vector_acceptance_prevented -or
    -not [bool]$mixedFrontend.vector_live_wave_tag_carried -or
    [bool]$mixedFrontend.vector_dependency_ready_external_input -or
    -not [bool]$mixedFrontend.matrix_scoreboard_dependency_source_integrated -or
    [bool]$mixedFrontend.full_compute_unit_scheduler_integrated -or
    [bool]$mixedFrontend.memory_execution_integrated -or
    -not [bool]$mixedFrontend.rtl_testbench_implemented) {
    Add-Finding "design/cgx1_architecture.json: mixed matrix/vector frontend RTL contract is incomplete"
}
if ([bool]$mixedFrontend.simulation_exercised) {
    Add-Finding "design/cgx1_architecture.json: mixed matrix/vector frontend simulation evidence must remain false until exact-revision RTL CI passes"
}
if ([bool]$mixedFrontend.timing_closure_validated -or
    [bool]$mixedFrontend.area_validated -or
    [bool]$mixedFrontend.power_validated) {
    Add-Finding "design/cgx1_architecture.json: mixed matrix/vector frontend must not claim unfinished physical evidence"
}

if ($findings.Count -gt 0) {
    Write-Host "Design consistency check failed:"
    $findings | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host "[pass] Design consistency check passed."
