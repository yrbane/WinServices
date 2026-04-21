# Stubs pour les cmdlets Windows-only permettant aux Mock Pester
# de fonctionner sous Linux/macOS (Get-Command ne les trouve pas
# sinon et Mock echoue avec CommandNotFoundException).

if (-not (Get-Command Get-Service -ErrorAction SilentlyContinue)) {
    function Get-Service { param($Name) }
    function Stop-Service { param($Name,[switch]$Force) }
    function Set-Service { param($Name,$StartupType) }
    function Start-Service { param($Name) }
}
if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
    function Get-ScheduledTask { param($TaskPath,$TaskName) }
    function Disable-ScheduledTask { param($TaskPath,$TaskName) }
    function Enable-ScheduledTask { param($TaskPath,$TaskName) }
}
if (-not (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue)) {
    function Get-WindowsOptionalFeature { param([switch]$Online,$FeatureName) }
    function Disable-WindowsOptionalFeature { param([switch]$Online,$FeatureName,[switch]$NoRestart) }
    function Enable-WindowsOptionalFeature { param([switch]$Online,$FeatureName,[switch]$NoRestart) }
}
if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
    function Get-AppxPackage { param($Name) }
    function Remove-AppxPackage { param($Package) }
}
if (-not (Get-Command Checkpoint-Computer -ErrorAction SilentlyContinue)) {
    function Enable-ComputerRestore { param($Drive) }
    function Checkpoint-Computer { param($Description,$RestorePointType) }
}
if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
    function Get-CimInstance { param($ClassName) }
}
