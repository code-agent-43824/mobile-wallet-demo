# Launches the built Windows app, watches it for -WatchSeconds and fails if it
# exits or Windows logs an application crash for it. Leaves a screenshot and
# the crash events (if any) in -OutDir for the run's artifacts.
#
#   pwsh scripts/smoke/launch_check_windows.ps1 -Exe build\windows\x64\runner\Release\WalletDemo.exe
param(
  [Parameter(Mandatory = $true)][string]$Exe,
  [string]$OutDir = "build/smoke",
  [int]$WatchSeconds = 30
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$started = Get-Date

Write-Host "== Launching $Exe =="
$process = Start-Process -FilePath $Exe -PassThru
$alive = $true
for ($i = 1; $i -le $WatchSeconds; $i++) {
  Start-Sleep -Seconds 1
  if ($process.HasExited) {
    Write-Host "  ~${i}s: the app exited with code $($process.ExitCode)"
    $alive = $false
    break
  }
}

Write-Host "== Screenshot =="
try {
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing
  $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
  $bitmap.Save((Join-Path $OutDir 'screenshot.png'), [System.Drawing.Imaging.ImageFormat]::Png)
} catch {
  Write-Host "  (no screenshot: $($_.Exception.Message))"
}

$name = [System.IO.Path]::GetFileName($Exe)
$crashes = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $started } -ErrorAction SilentlyContinue |
  Where-Object { ($_.ProviderName -in 'Application Error', 'Windows Error Reporting') -and $_.Message -like "*$name*" })
if ($crashes.Count -gt 0) {
  $crashes | Format-List TimeCreated, ProviderName, Message | Out-File (Join-Path $OutDir 'crash-events.txt')
  $crashes | Format-List TimeCreated, ProviderName, Message | Out-Host
}

if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }

if (-not $alive -or $crashes.Count -gt 0) {
  Write-Error "RESULT: the app crashed or exited within ${WatchSeconds}s."
  exit 1
}
Write-Host "RESULT: app stayed alive ${WatchSeconds}s - no crash detected."
