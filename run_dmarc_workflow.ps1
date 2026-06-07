<#
.SYNOPSIS
    Wrapper script to extract archive files and parse DMARC reports.
.DESCRIPTION
    This script takes two required parameters: a folder path and an output CSV file path.
    It runs extract_files.ps1 against the folder with archive deletion enabled.
    After extraction completes, it runs parse_dmarc_report.ps1 against the same folder,
    writes parsed CSV output to the specified file, and deletes processed XML files.
#>

param (
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$Path,

    [Parameter(Position = 1, Mandatory = $true)]
    [string]$OutputFile
)

# Resolve the provided folder path and ensure it points to an existing directory.
$folderPath = Resolve-Path -Path $Path -ErrorAction Stop | Select-Object -ExpandProperty Path
if (-not (Test-Path -Path $folderPath -PathType Container)) {
    Write-Error "Path must be an existing directory: $Path"
    exit 1
}

# Determine the location of the helper scripts relative to this wrapper script.
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$extractScript = Join-Path -Path $scriptRoot -ChildPath 'extract_files.ps1'
$parseScript = Join-Path -Path $scriptRoot -ChildPath 'parse_dmarc_report.ps1'

# Validate that the required helper scripts exist before continuing. If either script is missing, report an error and exit.
if (-not (Test-Path -Path $extractScript)) {
    Write-Error "Cannot find extract_files.ps1 in script folder: $scriptRoot"
    exit 1
}

if (-not (Test-Path -Path $parseScript)) {
    Write-Error "Cannot find parse_dmarc_report.ps1 in script folder: $scriptRoot"
    exit 1
}

# Run the archive extraction step with DeleteOriginal enabled.
Write-Host "Running extract_files.ps1 on: $folderPath"
$oldErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Stop'
try {
    & $extractScript -Directory $folderPath -DeleteOriginal $true
} catch {
    Write-Error "extract_files.ps1 failed: $($_.Exception.Message)"
    $ErrorActionPreference = $oldErrorActionPreference
    exit 1
}
$ErrorActionPreference = $oldErrorActionPreference

# Run the DMARC report parsing step with CSV output and delete original XML files.
Write-Host "Running parse_dmarc_report.ps1 on: $folderPath"
$oldErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Stop'
try {
    & $parseScript -Path $folderPath -OutputCsv $OutputFile -DeleteOriginal $true
} catch {
    Write-Error "parse_dmarc_report.ps1 failed: $($_.Exception.Message)"
    $ErrorActionPreference = $oldErrorActionPreference
    exit 1
}
$ErrorActionPreference = $oldErrorActionPreference

# Inform the user that the workflow completed successfully.
Write-Host "Workflow complete. CSV output written to: $OutputFile."