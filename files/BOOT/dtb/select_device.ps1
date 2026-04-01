#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$host.UI.RawUI.WindowTitle = "R36S / Clone / Soysauce DTB + Logo Selector"

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "   R36S DTB Firmware + Logo Selector"           -ForegroundColor Cyan
Write-Host "==================================================`n" -ForegroundColor Cyan

# Determine root folder
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ((Split-Path -Leaf $scriptDir) -eq "dtb") {
    $rootDir = Split-Path -Parent $scriptDir
} else {
    $rootDir = $scriptDir
}

Write-Host "Root folder: $rootDir" -ForegroundColor DarkCyan

# Find INI
$iniCandidates = @(
    (Join-Path $rootDir "r36_devices.ini"),
    (Join-Path $rootDir "dtb\r36_devices.ini")
)

$iniPath = $null
foreach ($candidate in $iniCandidates) {
    if (Test-Path $candidate) {
        $iniPath = $candidate
        Write-Host "Using INI: $iniPath" -ForegroundColor Green
        break
    }
}

if (-not $iniPath) {
    Write-Host "ERROR: r36_devices.ini not found" -ForegroundColor Red
    Pause
    exit 1
}

# Parse INI
Write-Host "`nReading devices..." -ForegroundColor Yellow

$sections = [ordered]@{}
$currentSection = $null

Get-Content $iniPath -Encoding UTF8 | ForEach-Object {
    $line = $_.Trim()
    if ($line -match '^\[(.+)\]$') {
        $currentSection = $matches[1].Trim()
        $sections[$currentSection] = @{}
    }
    elseif ($currentSection -and $line -match '^\s*([^=]+?)\s*=\s*(.+?)\s*$') {
        $key   = $matches[1].Trim()
        $value = $matches[2].Trim()
        $sections[$currentSection][$key] = $value
    }
}

if ($sections.Count -eq 0) {
    Write-Host "ERROR: No devices found in INI" -ForegroundColor Red
    Pause
    exit 1
}

# Group by variant
$grouped = [ordered]@{}

foreach ($dev in $sections.Keys) {
    $v = $sections[$dev]['variant']
    if (-not $v) { $v = "unknown" }

    if (-not $grouped.Contains($v)) {
        $grouped[$v] = New-Object System.Collections.ArrayList
    }
    $null = $grouped[$v].Add($dev)
}

$variantDisplayOrder = @("r36s", "clone", "soysauce")
$sortedVariants = $variantDisplayOrder | Where-Object { $grouped.Contains($_) }
$sortedVariants += ($grouped.Keys | Where-Object { $_ -notin $variantDisplayOrder })

# Two-column menu
Write-Host "`nAvailable devices:" -ForegroundColor Cyan
Write-Host ""

$globalIndex = 1
$deviceList = @{}   # Device selection lookup

foreach ($variant in $sortedVariants) {
    $devicesInGroup = $grouped[$variant]

    if ($devicesInGroup.Count -eq 0) { continue }

    Write-Host "Variant: $variant" -ForegroundColor Magenta
    Write-Host ("-" * 70) -ForegroundColor DarkGray

    $half = [math]::Ceiling($devicesInGroup.Count / 2)

    for ($row = 0; $row -lt $half; $row++) {
        $leftPart = ""
        $rightPart = ""

        # Left column
        if ($row -lt $devicesInGroup.Count) {
            $num = $globalIndex
            $leftPart = "{0,4}. {1}" -f $num, $devicesInGroup[$row]
            $deviceList[$num] = $devicesInGroup[$row]
            $globalIndex++
        }

        # Right column
        $rightIdx = $row + $half
        if ($rightIdx -lt $devicesInGroup.Count) {
            $num = $globalIndex
            $rightPart = "{0,4}. {1}" -f $num, $devicesInGroup[$rightIdx]
            $deviceList[$num] = $devicesInGroup[$rightIdx]
            $globalIndex++
        }

        Write-Host ("{0,-40}{1}" -f $leftPart, $rightPart)
    }

    Write-Host ""
}

Write-Host ("=" * 70) -ForegroundColor DarkGray
Write-Host "Total: $($sections.Count) devices" -ForegroundColor Cyan

# Selection
Write-Host "`nSelect number (1-$($sections.Count))" -ForegroundColor Cyan
$rawInput = Read-Host
$selection = $rawInput.Trim()

if ($selection -eq '' -or $selection -notmatch '^\d+$') {
    Write-Host "Please enter a valid number." -ForegroundColor Red
    Pause
    exit 1
}

$selNum = [int]$selection

if ($selNum -lt 1 -or $selNum -gt $sections.Count) {
    Write-Host "Number must be between 1 and $($sections.Count)" -ForegroundColor Red
    Pause
    exit 1
}

$chosen  = $deviceList[$selNum]
$variant = $sections[$chosen]['variant']

Write-Host "`nSelected : $chosen" -ForegroundColor Green
Write-Host "Variant  : $variant" -ForegroundColor Green

# ── Get resolution for logo selection ─────────────────────────────────────
$resolution = ""
if ($sections[$chosen].ContainsKey('resolution')) {
    $resolution = $sections[$chosen]['resolution'].Trim()
}

$logoSrc = $null
if ($resolution -eq "640x480") {
    $logoSrc = Join-Path $rootDir "dtb\logo\logo-640x480.bmp"
    Write-Host "Using 640x480 logo" -ForegroundColor Cyan
} elseif ($resolution -eq "720x720") {
    $logoSrc = Join-Path $rootDir "dtb\logo\logo-720x720.bmp"
    Write-Host "Using 720x720 logo" -ForegroundColor Cyan
} else {
    Write-Host "WARNING: No valid resolution found for $chosen (got: '$resolution'). No logo will be copied." -ForegroundColor Yellow
}

# Build source folder
$sourceFolder = Join-Path $rootDir "dtb\$variant\$chosen"

if (-not (Test-Path $sourceFolder -PathType Container)) {
    Write-Host "ERROR: Folder not found: $sourceFolder" -ForegroundColor Red
    Pause
    exit 1
}

# Preview
Write-Host "`nWill copy DTB files from:" -ForegroundColor Cyan
Write-Host "  $sourceFolder" -ForegroundColor White

if ($logoSrc -and (Test-Path $logoSrc)) {
    Write-Host "`nWill replace logo.bmp with:" -ForegroundColor Cyan
    Write-Host "  $logoSrc to logo.bmp" -ForegroundColor White
}

Write-Host "`n.dtbfiles in root that will be deleted/overwritten:"
$existingDtbs = @(Get-ChildItem -Path $rootDir -File -Filter "*.dtb" -ErrorAction SilentlyContinue)
if ($existingDtbs.Count -eq 0) {
    Write-Host "  (none currently present)"
} else {
    $existingDtbs | ForEach-Object { "  $($_.Name)" }
}

Write-Host ""
$confirm = Read-Host "Proceed with copy + logo update? (Y/N)"
if ($confirm -notmatch '^[Yy]$') {
    Write-Host "Cancelled." -ForegroundColor Yellow
    Pause
    exit 0
}

# === Apply changes ===
Write-Host "`nDeleting old .dtb files in root..." -ForegroundColor Yellow
Get-ChildItem -Path $rootDir -Filter "*.dtb" -File | ForEach-Object {
    Remove-Item $_.FullName -Force
    Write-Host "  Deleted $($_.Name)"
}

Write-Host "`nRemoving existing logo.bmp..." -ForegroundColor Yellow
$oldLogo = Join-Path $rootDir "logo.bmp"
if (Test-Path $oldLogo) {
    Remove-Item $oldLogo -Force
    Write-Host "  logo.bmp deleted"
} else {
    Write-Host "  No logo.bmp present"
}

Write-Host "`nCopying new DTB files to root..." -ForegroundColor Yellow
$copied = Copy-Item -Path "$sourceFolder\*" -Destination $rootDir -Force -Include "*.dtb" -PassThru -ErrorAction Stop
if ($copied.Count -gt 0) {
    $copied | ForEach-Object { Write-Host "  Copied $($_.Name)" }
} else {
    Write-Host "  No DTB files copied" -ForegroundColor Yellow
}

# Copy correct logo and rename to logo.bmp
if ($logoSrc -and (Test-Path $logoSrc)) {
    Write-Host "`nInstalling logo..." -ForegroundColor Yellow
    Copy-Item -Path $logoSrc -Destination (Join-Path $rootDir "logo.bmp") -Force
    Write-Host "  logo.bmp installed (from $resolution resolution)"
} else {
    Write-Host "  No logo installed (missing source or unknown resolution)" -ForegroundColor Yellow
}

Write-Host "`n==================================================" -ForegroundColor Green
Write-Host "   SUCCESS - DTB + Logo updated for:"           -ForegroundColor Green
Write-Host "   $chosen"                                     -ForegroundColor White
Write-Host "   Variant: $variant"                           -ForegroundColor White
Write-Host "   Resolution: $resolution"                     -ForegroundColor White
Write-Host "==================================================`n" -ForegroundColor Green
