<#
.SYNOPSIS
    Audit avancé des services Windows -> export JSON enrichi (FR/EN)

.DESCRIPTION
    Scan complet des services Windows avec enrichissement :
      - Infos service (EN + FR)
      - Exécutable + metadata
      - Signature numérique
      - Hash SHA256
      - Dépendances structurées
      - Infos système

    Lecture seule, aucun changement système.

.EXAMPLE
    .\Audit-Services-JSON.ps1 -All

#>

[CmdletBinding()]
param(
    [switch]$All,
    [string]$OutputPath = [Environment]::GetFolderPath('Desktop')
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath | Out-Null
}

$timestamp = (Get-Date).ToString("yyyy-MM-ddTHH-mm-ss")
$jsonPath  = Join-Path $OutputPath "WindowsServices-Audit-$timestamp.json"

Write-Host "Collecte des services..." -ForegroundColor Cyan

$cimServices = Get-CimInstance Win32_Service

if (-not $All) {
    $cimServices = $cimServices | Where-Object { $_.State -eq 'Running' }
}

$fileCache = @{}

function Resolve-Exe {
    param([string]$PathName)

    if (!$PathName) { return $null }

    $exe = $PathName.Trim()

    if ($exe.StartsWith('"')) {
        $exe = $exe.Split('"')[1]
    } else {
        $exe = $exe.Split(' ')[0]
    }

    return $exe
}

function Get-FileMeta {
    param([string]$exe)

    if (!$exe -or $fileCache.ContainsKey($exe)) {
        return $fileCache[$exe]
    }

    $meta = [ordered]@{
        path        = $exe
        exists      = $false
        company     = $null
        product     = $null
        description = $null
        version     = $null
        sha256      = $null
        signature   = $null
        isMicrosoft = $false
    }

    if (Test-Path $exe) {
        $meta.exists = $true

        try {
            $vi = (Get-Item $exe).VersionInfo
            $meta.company     = $vi.CompanyName
            $meta.product     = $vi.ProductName
            $meta.description = $vi.FileDescription
            $meta.version     = $vi.FileVersion

            $meta.isMicrosoft = (
                $vi.CompanyName -like '*Microsoft*' -or
                $exe -like "$env:SystemRoot\System32\*" -or
                $exe -like "$env:SystemRoot\SysWOW64\*"
            )

            $meta.sha256 = (Get-FileHash $exe -Algorithm SHA256).Hash

            $sig = Get-AuthenticodeSignature $exe
            $meta.signature = $sig.Status
        }
        catch {}
    }

    $fileCache[$exe] = $meta
    return $meta
}

$result = foreach ($svc in $cimServices) {

    $exe = Resolve-Exe $svc.PathName
    $meta = Get-FileMeta $exe

    $deps = @()
    $dependsOn = @()

    try {
        $gs = Get-Service $svc.Name
        $deps      = $gs.DependentServices | ForEach-Object { $_.Name }
        $dependsOn = $gs.ServicesDependedOn | ForEach-Object { $_.Name }
    } catch {}

    [ordered]@{

        system = @{
            computerName = $env:COMPUTERNAME
            timestamp    = (Get-Date).ToString("o")
            os           = (Get-CimInstance Win32_OperatingSystem).Caption
        }

        service = @{
            name = @{
                en = $svc.Name
                fr = "Nom du service"
            }
            displayName = @{
                en = $svc.DisplayName
                fr = "Nom affiché"
            }
            description = @{
                en = $svc.Description
                fr = "Description"
            }
            state = @{
                en = $svc.State
                fr = switch ($svc.State) {
                    "Running" { "En cours" }
                    "Stopped" { "Arrêté" }
                    default { $svc.State }
                }
            }
            startType = @{
                en = $svc.StartMode
                fr = switch ($svc.StartMode) {
                    "Auto" { "Automatique" }
                    "Manual" { "Manuel" }
                    "Disabled" { "Désactivé" }
                    default { $svc.StartMode }
                }
            }
            delayedAutoStart = $svc.DelayedAutoStart
            account = $svc.StartName
            processId = $svc.ProcessId
        }

        executable = $meta

        dependencies = @{
            dependsOn        = $dependsOn
            dependentServices = $deps
        }
    }
}

Write-Host "Export JSON..." -ForegroundColor Cyan

$result | ConvertTo-Json -Depth 6 | Out-File $jsonPath -Encoding UTF8

Write-Host ""
Write-Host "Terminé ✅" -ForegroundColor Green
Write-Host "Fichier : $jsonPath"