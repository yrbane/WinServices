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
# Populated in subsequent tasks
#endregion

#region Main
if ($MyInvocation.InvocationName -ne '.') {
    # Orchestration only runs when invoked directly (not dot-sourced for tests)
    # To be implemented in Task 15
    Write-Host 'Script skeleton - orchestration not yet implemented.' -ForegroundColor Yellow
}
#endregion
