<#
.SYNOPSIS
    Optimiseur interactif Windows 11 - desactive services, taches planifiees,
    fonctionnalites optionnelles et paquets AppX selon les reponses utilisateur.
.NOTES
    Cible : Windows 11 build >= 22621 (22H2+). Execution en mode administrateur requise.
#>
[CmdletBinding()]
param(
    [Parameter()] [string] $CatalogPath = "$PSScriptRoot/catalog.json",
    [Parameter()] [string] $BackupRoot  = "$PSScriptRoot/backups",
    [Parameter()] [switch] $DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Compat PowerShell 5.1 : les variables automatiques $IsLinux / $IsMacOS / $IsWindows
# n'existent qu'a partir de PowerShell 6. Sous Set-StrictMode, leur absence plante.
if (-not (Get-Variable -Name IsWindows -Scope Global -ErrorAction SilentlyContinue)) {
    $global:IsWindows = $true
}
if (-not (Get-Variable -Name IsLinux -Scope Global -ErrorAction SilentlyContinue)) {
    $global:IsLinux = $false
}
if (-not (Get-Variable -Name IsMacOS -Scope Global -ErrorAction SilentlyContinue)) {
    $global:IsMacOS = $false
}

#region Constants
$script:MinWindowsBuild = 22621
$script:ProtectedServices = @(
    'AudioSrv','AudioEndpointBuilder','BFE','CryptSvc','Dhcp','Dnscache',
    'EventLog','LSM','MpsSvc','NlaSvc','Power','ProfSvc','RpcEptMapper',
    'RpcSs','Schedule','SENS','Themes','UserManager','WinDefend','Winmgmt','wscsvc'
)
#endregion

#region Functions
function Write-Info    { param([string]$Message) Write-Host $Message -ForegroundColor Gray }
function Write-Ask     { param([string]$Message) Write-Host $Message -ForegroundColor Cyan }
function Write-Warn    { param([string]$Message) Write-Host $Message -ForegroundColor Yellow }
function Write-Danger  { param([string]$Message) Write-Host $Message -ForegroundColor Red }
function Write-Success { param([string]$Message) Write-Host $Message -ForegroundColor Green }

function Read-YesNoSkip {
    param(
        [Parameter(Mandatory)][string] $Prompt,
        [ValidateSet('yes','no','skip')][string] $Default = 'no'
    )
    while ($true) {
        $answer = (Read-Host -Prompt "$Prompt [O]ui / [N]on / [S]kip (passer)").Trim().ToLowerInvariant()
        switch ($answer) {
            { $_ -in 'o','y','oui','yes' } { return 'yes' }
            { $_ -in 'n','non','no' }      { return 'no' }
            { $_ -in 's','skip','passer' } { return 'skip' }
            ''                             { return $Default }
            default {
                Write-Warn "Reponse invalide. Tapez O (Oui), N (Non) ou S (Skip = passer cet item sans le modifier)."
            }
        }
    }
}

function New-BackupDirectory {
    param([Parameter(Mandatory)][string] $Root)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir = Join-Path $Root $stamp
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Export-StateSnapshot {
    param(
        [Parameter(Mandatory)][ValidateSet('service','task','feature','appx')][string] $Type,
        [Parameter(Mandatory)][string[]] $Names,
        [Parameter(Mandatory)][string] $OutputDir
    )
    $fileName = switch ($Type) {
        'service' { 'services.csv' }
        'task'    { 'tasks.csv' }
        'feature' { 'features.csv' }
        'appx'    { 'appx.csv' }
    }
    $outPath = Join-Path $OutputDir $fileName

    $rows = switch ($Type) {
        'service' {
            foreach ($n in $Names) {
                try {
                    $s = Get-Service -Name $n -ErrorAction Stop
                    [pscustomobject]@{
                        Name = $s.Name; DisplayName = $s.DisplayName
                        Status = [string]$s.Status; StartType = [string]$s.StartType
                    }
                } catch { }
            }
        }
        'task' {
            foreach ($n in $Names) {
                $parts = Split-TaskPath -FullPath $n
                try {
                    $t = Get-ScheduledTask -TaskPath $parts.TaskPath -TaskName $parts.TaskName -ErrorAction Stop
                    [pscustomobject]@{ TaskPath = $t.TaskPath; TaskName = $t.TaskName; State = [string]$t.State }
                } catch { }
            }
        }
        'feature' {
            foreach ($n in $Names) {
                try {
                    $f = Get-WindowsOptionalFeature -Online -FeatureName $n -ErrorAction Stop
                    [pscustomobject]@{ FeatureName = $f.FeatureName; State = [string]$f.State }
                } catch { }
            }
        }
        'appx' {
            foreach ($n in $Names) {
                try {
                    $p = Get-AppxPackage -Name $n -ErrorAction Stop | Select-Object -First 1
                    if ($p) {
                        [pscustomobject]@{ Name = $p.Name; PackageFullName = $p.PackageFullName; Publisher = $p.Publisher }
                    }
                } catch { }
            }
        }
    }

    if ($rows) {
        $rows | Export-Csv -LiteralPath $outPath -NoTypeInformation -Encoding UTF8
    } else {
        Set-Content -LiteralPath $outPath -Value '' -Encoding UTF8
    }
    return $outPath
}

function New-SystemRestorePoint {
    param([Parameter(Mandatory)][string] $Description)
    try {
        Enable-ComputerRestore -Drive 'C:\' -ErrorAction Stop
        Checkpoint-Computer -Description $Description -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        return $true
    } catch {
        Write-Warning "Impossible de creer un point de restauration : $($_.Exception.Message)"
        return $false
    }
}

function Add-RestoreCommand {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Command
    )
    Add-Content -LiteralPath $Path -Value $Command -Encoding UTF8
}

function Disable-ServiceItem {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $RestoreScriptPath,
        [switch] $DryRun
    )
    if ($Name -in $script:ProtectedServices) {
        throw "Service protege, refus de desactivation : $Name"
    }
    try {
        $svc = Get-Service -Name $Name -ErrorAction Stop
    } catch {
        return [pscustomobject]@{ Success = $false; Reason = "Service introuvable : $Name" }
    }

    $originalStartType = [string]$svc.StartType
    $wasRunning = ($svc.Status -eq 'Running')

    if ($DryRun) {
        Write-Info "[DRYRUN] Desactiverait le service '$Name' (etat initial : $originalStartType / $($svc.Status))"
        return [pscustomobject]@{ Success = $true; Reason = 'DryRun' }
    }

    try {
        if ($wasRunning) { Stop-Service -Name $Name -Force -ErrorAction Stop }
        Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
    } catch {
        return [pscustomobject]@{ Success = $false; Reason = $_.Exception.Message }
    }

    Add-RestoreCommand -Path $RestoreScriptPath -Command "Set-Service -Name '$Name' -StartupType $originalStartType"
    if ($wasRunning) {
        Add-RestoreCommand -Path $RestoreScriptPath -Command "Start-Service -Name '$Name'"
    }
    return [pscustomobject]@{ Success = $true; Reason = 'OK' }
}

function Split-TaskPath {
    # Decoupe un chemin de tache planifiee Windows (toujours avec '\' comme separateur)
    # de maniere portable (Split-Path natif ne gere pas '\' sous Linux).
    param([Parameter(Mandatory)][string] $FullPath)
    $lastSep = $FullPath.LastIndexOf('\')
    if ($lastSep -lt 0) {
        return [pscustomobject]@{ TaskPath = '\'; TaskName = $FullPath }
    }
    $parent = $FullPath.Substring(0, $lastSep)
    $leaf   = $FullPath.Substring($lastSep + 1)
    if (-not $parent.EndsWith('\')) { $parent += '\' }
    return [pscustomobject]@{ TaskPath = $parent; TaskName = $leaf }
}

function Disable-TaskItem {
    param(
        [Parameter(Mandatory)][string] $FullPath,
        [Parameter(Mandatory)][string] $RestoreScriptPath,
        [switch] $DryRun
    )
    $parts = Split-TaskPath -FullPath $FullPath
    $taskPath = $parts.TaskPath
    $leaf     = $parts.TaskName

    try {
        $task = Get-ScheduledTask -TaskPath $taskPath -TaskName $leaf -ErrorAction Stop
    } catch {
        return [pscustomobject]@{ Success = $false; Reason = "Tache introuvable : $FullPath" }
    }

    if ($DryRun) {
        Write-Info "[DRYRUN] Desactiverait la tache '$FullPath' (etat initial : $($task.State))"
        return [pscustomobject]@{ Success = $true; Reason = 'DryRun' }
    }

    try {
        Disable-ScheduledTask -TaskPath $taskPath -TaskName $leaf -ErrorAction Stop | Out-Null
    } catch {
        return [pscustomobject]@{ Success = $false; Reason = $_.Exception.Message }
    }

    Add-RestoreCommand -Path $RestoreScriptPath -Command "Enable-ScheduledTask -TaskPath '$taskPath' -TaskName '$leaf'"
    return [pscustomobject]@{ Success = $true; Reason = 'OK' }
}

function Disable-FeatureItem {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $RestoreScriptPath,
        [switch] $DryRun
    )
    try {
        $f = Get-WindowsOptionalFeature -Online -FeatureName $Name -ErrorAction Stop
    } catch {
        return [pscustomobject]@{ Success = $false; Reason = "Fonctionnalite introuvable : $Name" }
    }

    if ([string]$f.State -eq 'Disabled') {
        return [pscustomobject]@{ Success = $true; Reason = 'Deja desactivee' }
    }

    if ($DryRun) {
        Write-Info "[DRYRUN] Desactiverait la feature '$Name'"
        return [pscustomobject]@{ Success = $true; Reason = 'DryRun' }
    }

    try {
        Disable-WindowsOptionalFeature -Online -FeatureName $Name -NoRestart -ErrorAction Stop | Out-Null
    } catch {
        return [pscustomobject]@{ Success = $false; Reason = $_.Exception.Message }
    }

    Add-RestoreCommand -Path $RestoreScriptPath -Command "Enable-WindowsOptionalFeature -Online -FeatureName '$Name' -NoRestart"
    return [pscustomobject]@{ Success = $true; Reason = 'OK' }
}

function Remove-AppxItem {
    param(
        [Parameter(Mandatory)][string] $Name,
        [Parameter(Mandatory)][string] $RestoreScriptPath,
        [switch] $DryRun
    )
    $pkg = Get-AppxPackage -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $pkg) {
        return [pscustomobject]@{ Success = $true; Reason = 'Paquet absent' }
    }

    if ($DryRun) {
        Write-Info "[DRYRUN] Desinstallerait le paquet AppX '$Name'"
        return [pscustomobject]@{ Success = $true; Reason = 'DryRun' }
    }

    try {
        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
    } catch {
        return [pscustomobject]@{ Success = $false; Reason = $_.Exception.Message }
    }

    Add-RestoreCommand -Path $RestoreScriptPath -Command "# $($pkg.Name) : desinstalle. Paquet original : $($pkg.PackageFullName)"
    Add-RestoreCommand -Path $RestoreScriptPath -Command "# Pour restaurer : reinstaller via Microsoft Store."
    return [pscustomobject]@{ Success = $true; Reason = 'OK' }
}

function Invoke-ItemAction {
    param(
        [Parameter(Mandatory)] $Item,
        [Parameter(Mandatory)][string] $RestoreScriptPath,
        [switch] $DryRun
    )
    switch ($Item.type) {
        'service' { return Disable-ServiceItem -Name $Item.name -RestoreScriptPath $RestoreScriptPath -DryRun:$DryRun }
        'task'    { return Disable-TaskItem -FullPath $Item.name -RestoreScriptPath $RestoreScriptPath -DryRun:$DryRun }
        'feature' { return Disable-FeatureItem -Name $Item.name -RestoreScriptPath $RestoreScriptPath -DryRun:$DryRun }
        'appx'    { return Remove-AppxItem -Name $Item.name -RestoreScriptPath $RestoreScriptPath -DryRun:$DryRun }
        default   { throw "Type d'item inconnu : $($Item.type)" }
    }
}

function Initialize-RestoreScript {
    param([Parameter(Mandatory)][string] $BackupDir)
    $stamp = Split-Path $BackupDir -Leaf
    $path = Join-Path $BackupDir "Restore-$stamp.ps1"
    $header = @"
# Script de restauration - $stamp
# Genere par Optimize-Windows.ps1
#Requires -RunAsAdministrator

Write-Host 'Restauration en cours...' -ForegroundColor Cyan

"@
    Set-Content -LiteralPath $path -Value $header -Encoding UTF8
    return $path
}

function Invoke-Optimization {
    param(
        [Parameter(Mandatory)][string] $CatalogPath,
        [Parameter(Mandatory)][string] $BackupRoot,
        [switch] $DryRun
    )

    if (-not (Test-IsElevated)) {
        Write-Danger 'Execution administrateur requise.'
        return [pscustomobject]@{ ExitCode = 1 }
    }
    $build = Get-CurrentWindowsBuild
    if (-not (Test-WindowsCompatible -CurrentBuild $build -MinBuild $script:MinWindowsBuild)) {
        Write-Danger "Windows build $build < $($script:MinWindowsBuild) (22H2). Abort."
        return [pscustomobject]@{ ExitCode = 2 }
    }

    $catalog = Read-Catalog -Path $CatalogPath
    Test-CatalogStructure -Catalog $catalog

    Write-Warn 'Cet outil va desactiver des composants Windows selon tes reponses.'
    Write-Warn 'Un point de restauration et des CSV de sauvegarde seront crees.'
    if (-not $DryRun) {
        if ((Read-YesNoSkip -Prompt 'Continuer ?') -ne 'yes') {
            return [pscustomobject]@{ ExitCode = 3 }
        }
    }

    $backupDir = New-BackupDirectory -Root $BackupRoot
    $restoreScript = Initialize-RestoreScript -BackupDir $backupDir

    $allItems = @()
    foreach ($c in $catalog.categories) { $allItems += $c.items }
    $allItems += $catalog.advanced

    $byType = @{}
    foreach ($t in 'service','task','feature','appx') {
        $byType[$t] = @($allItems | Where-Object { $_.type -eq $t } | ForEach-Object { $_.name })
    }

    foreach ($t in 'service','task','feature','appx') {
        if ($byType[$t].Count -gt 0) {
            Export-StateSnapshot -Type $t -Names $byType[$t] -OutputDir $backupDir | Out-Null
        }
    }

    if (-not $DryRun) {
        New-SystemRestorePoint -Description 'Pre-Optimize-Windows' | Out-Null
    }

    $decisions = @()
    $decisions += Invoke-CategoryPhase -Catalog $catalog
    $decisions += Invoke-AdvancedPhase -Catalog $catalog

    Show-Summary -Decisions $decisions -DryRun:$DryRun
    if (-not (Read-FinalConfirmation -DryRun:$DryRun)) {
        Write-Warn 'Annule par l utilisateur.'
        return [pscustomobject]@{ ExitCode = 4 }
    }

    $successes = 0; $failures = 0
    foreach ($item in $decisions) {
        $r = Invoke-ItemAction -Item $item -RestoreScriptPath $restoreScript -DryRun:$DryRun
        if ($r.Success) {
            Write-Success "[OK] $($item.type) $($item.name) - $($r.Reason)"
            $successes++
        } else {
            Write-Danger  "[KO] $($item.type) $($item.name) - $($r.Reason)"
            $failures++
        }
    }

    Write-Host ''
    Write-Success ("Termine : {0} succes, {1} echecs" -f $successes, $failures)
    Write-Info    "Sauvegardes : $backupDir"
    Write-Info    "Script de restauration : $restoreScript"
    if (-not $DryRun) { Write-Warn 'Redemarrage recommande pour effet complet.' }

    return [pscustomobject]@{ ExitCode = 0; Successes = $successes; Failures = $failures }
}

function Invoke-CategoryPhase {
    param([Parameter(Mandatory)] $Catalog)
    $decisions = New-Object System.Collections.Generic.List[object]

    foreach ($cat in $Catalog.categories) {
        Write-Host ''
        Write-Ask "[$($cat.id)] $($cat.question)"
        Write-Info "  Impact : $(($cat.items | ForEach-Object { '{0}:{1}' -f $_.type, $_.name }) -join ', ')"

        $answer = Read-YesNoSkip -Prompt 'Reponse'
        if ($answer -eq 'skip') { continue }

        $disable = if ($cat.keepIfYes) { $answer -eq 'no' } else { $answer -eq 'yes' }
        if ($disable) {
            foreach ($it in $cat.items) { $decisions.Add($it) }
        }
    }
    return ,$decisions
}

function Invoke-AdvancedPhase {
    param([Parameter(Mandatory)] $Catalog)
    $decisions = New-Object System.Collections.Generic.List[object]

    if (-not $Catalog.advanced -or $Catalog.advanced.Count -eq 0) { return $decisions }

    Write-Host ''
    Write-Warn '--- Section avancee (item par item) ---'

    foreach ($it in $Catalog.advanced) {
        $desc = if ($it.PSObject.Properties.Name -contains 'description') { $it.description } else { '' }
        Write-Ask "Desactiver $($it.type) '$($it.name)' ? $desc"
        if ((Read-YesNoSkip -Prompt 'Reponse') -eq 'yes') {
            $decisions.Add($it)
        }
    }
    return ,$decisions
}

function Get-SummaryCounts {
    param([Parameter(Mandatory)] $Decisions)
    $result = [ordered]@{ service = 0; task = 0; feature = 0; appx = 0 }
    foreach ($d in $Decisions) {
        if ($result.Contains($d.type)) { $result[$d.type]++ }
    }
    return [pscustomobject]$result
}

function Show-Summary {
    param(
        [Parameter(Mandatory)] $Decisions,
        [switch] $DryRun
    )
    $c = Get-SummaryCounts -Decisions $Decisions
    Write-Host ''
    Write-Warn '=== Recapitulatif ==='
    Write-Host ("Services a desactiver  : {0}" -f $c.service)
    Write-Host ("Taches a desactiver    : {0}" -f $c.task)
    Write-Host ("Features a desactiver  : {0}" -f $c.feature)
    Write-Host ("Paquets AppX a retirer : {0}" -f $c.appx)
    Write-Host ("Total                  : {0}" -f $Decisions.Count)
    if ($DryRun) { Write-Warn '(MODE DRYRUN - aucune modification ne sera appliquee)' }
}

function Read-FinalConfirmation {
    param([switch] $DryRun)
    if ($DryRun) { return $true }
    return (Read-YesNoSkip -Prompt 'Appliquer les modifications ?') -eq 'yes'
}

function Test-IsElevated {
    if ($IsLinux -or $IsMacOS) { return $false }
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-CurrentWindowsBuild {
    if ($IsLinux -or $IsMacOS) { return 0 }
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        return [int]($os.BuildNumber)
    } catch {
        return 0
    }
}

function Test-WindowsCompatible {
    param(
        [Parameter(Mandatory)][int] $CurrentBuild,
        [Parameter(Mandatory)][int] $MinBuild
    )
    return $CurrentBuild -ge $MinBuild
}

function Read-Catalog {
    param([Parameter(Mandatory)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Fichier catalogue introuvable : $Path"
    }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    try {
        return $raw | ConvertFrom-Json
    } catch {
        throw "catalog.json invalide : $($_.Exception.Message)"
    }
}

function Test-CatalogStructure {
    param([Parameter(Mandatory)] $Catalog)

    foreach ($field in 'version','minWindowsBuild','categories','advanced') {
        if (-not ($Catalog.PSObject.Properties.Name -contains $field)) {
            throw "Champ manquant dans le catalogue : $field"
        }
    }

    $validTypes = 'service','task','feature','appx'
    $allItems = @()
    foreach ($cat in $Catalog.categories) {
        foreach ($f in 'id','question','keepIfYes','items') {
            if (-not ($cat.PSObject.Properties.Name -contains $f)) {
                throw "Champ manquant dans la categorie : $f"
            }
        }
        $allItems += $cat.items
    }
    $allItems += $Catalog.advanced

    foreach ($item in $allItems) {
        if ($item.type -notin $validTypes) {
            throw "type invalide pour '$($item.name)' : $($item.type)"
        }
        if ($item.type -eq 'service' -and $item.name -in $script:ProtectedServices) {
            throw "Service protege dans le catalogue : $($item.name)"
        }
    }
}
#endregion

#region Main
if ($MyInvocation.InvocationName -ne '.') {
    $result = Invoke-Optimization -CatalogPath $CatalogPath -BackupRoot $BackupRoot -DryRun:$DryRun
    exit $result.ExitCode
}
#endregion
