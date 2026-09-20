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

Require-Literal "docs/THERMAL_POWER.md" "| **Total** | **$fullPower W** |"
Require-Literal "docs/MECHANICAL_DESIGN.md" ("The revised dock target is **$dockLength " + $multiply + " $dockWidth " + $multiply + " $dockHeight mm**.")
Require-Literal "docs/ELECTRICAL_INTERFACE.md" "returns directly to **P0 Safe Boot**"
Require-Literal "docs/STATUS.md" "$fp32 TFLOPS"
Require-Literal "docs/ENGINEERING_SPEC.md" "$l1Shared KB combined L1/shared memory per compute unit target."
Require-Literal "docs/ENGINEERING_SPEC.md" "$l2PerTile MB L2 slice per compute tile."
Require-Literal "docs/ENGINEERING_SPEC.md" "$l2Total MB aggregate L2 target."
Require-Literal "README.md" "| Package level cache target | $packageCache MB | Architecture target |"

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

if ($findings.Count -gt 0) {
    Write-Host "Design consistency check failed:"
    $findings | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host "[pass] Design consistency check passed."
