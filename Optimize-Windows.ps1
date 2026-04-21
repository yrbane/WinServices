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

#region Constants
$script:MinWindowsBuild = 22621
$script:ProtectedServices = @(
    'AudioSrv','AudioEndpointBuilder','BFE','CryptSvc','Dhcp','Dnscache',
    'EventLog','LSM','MpsSvc','NlaSvc','Power','ProfSvc','RpcEptMapper',
    'RpcSs','Schedule','SENS','Themes','UserManager','WinDefend','Winmgmt','wscsvc'
)
#endregion

#region Functions
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
    # Orchestration only runs when invoked directly (not dot-sourced for tests)
    # To be implemented in Task 15
    Write-Host 'Script skeleton - orchestration not yet implemented.' -ForegroundColor Yellow
}
#endregion
