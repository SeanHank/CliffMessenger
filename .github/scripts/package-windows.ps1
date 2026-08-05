<#
.SYNOPSIS
  Package the Flutter Windows release build into a distributable zip.

.PARAMETER Version
  Semantic version string (e.g. 2026.4.6).

.PARAMETER AppName
  Binary/app name (e.g. cliff_messenger).
#>
param(
  [Parameter(Mandatory = $true)] [string] $Version,
  [Parameter(Mandatory = $true)] [string] $AppName
)

$ErrorActionPreference = 'Stop'

$ReleaseDir = Join-Path (Get-Location) 'build\windows\x64\runner\Release'
if (-not (Test-Path $ReleaseDir)) {
  throw "Windows release dir not found: $ReleaseDir — did 'flutter build windows' run?"
}

# Sanity: the main executable must be present.
$Exe = Join-Path $ReleaseDir "$AppName.exe"
if (-not (Test-Path $Exe)) {
  Write-Host "Warning: $Exe not found; packaging the whole Release folder anyway."
}

$ArtifactsDir = Join-Path (Get-Location) 'artifacts'
New-Item -ItemType Directory -Force -Path $ArtifactsDir | Out-Null

$ZipName = "$AppName-$Version-windows.zip"
$ZipPath = Join-Path $ArtifactsDir $ZipName

if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

# Use .NET System.IO.Compression to avoid depending on 7-Zip / Compress-Archive
# quirks with long relative paths. Zip from inside Release so the .exe sits at
# the archive root.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$Parent = Split-Path -Parent $ReleaseDir
$Leaf   = Split-Path -Leaf  $ReleaseDir
[System.IO.Compression.ZipFile]::CreateFromDirectory($ReleaseDir, $ZipPath,
  [System.IO.Compression.CompressionLevel]::Optimal, $false)

$Size = (Get-Item $ZipPath).Length
Write-Host "Packaged $ZipPath ($([math]::Round($Size / 1MB, 2)) MB)"

Get-ChildItem $ArtifactsDir | Format-Table Name, Length
