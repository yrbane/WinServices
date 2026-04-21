# Windows Services Optimizer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an interactive PowerShell script that disables unused Windows 11 services, scheduled tasks, optional features, and AppX packages based on user usage questions — with a system restore point, CSV state backups, and a generated rollback script.

**Architecture:** Single PowerShell script `Optimize-Windows.ps1` containing well-organized functions (regions), orchestrating a data-driven flow from `catalog.json`. Functions are dot-sourceable for Pester unit tests; orchestration only runs when the script is invoked directly (not dot-sourced). Four type-dispatched handlers (service / task / feature / appx) apply changes.

**Tech Stack:** PowerShell 5.1+ (Windows 11 shipped), Pester 5.x for tests, native Windows cmdlets (`Get-Service`, `Get-ScheduledTask`, `Get-WindowsOptionalFeature`, `Get-AppxPackage`).

---

## File Structure

```
WinServices/
├── Optimize-Windows.ps1              # Engine (functions + orchestration guard)
├── catalog.json                      # Data catalog (14 categories + advanced items)
├── README.md                         # Usage documentation + warnings
├── .gitignore                        # Ignore backups/
├── tests/
│   ├── Catalog.Tests.ps1             # Catalog schema validation
│   ├── Environment.Tests.ps1         # Admin / build checks
│   ├── Backup.Tests.ps1              # State snapshot exports
│   ├── Handlers.Tests.ps1            # 4 handlers (disable + restore-append)
│   └── Orchestration.Tests.ps1       # End-to-end with DryRun
└── backups/                          # Generated at runtime (gitignored)
```

**Responsibility per file:**
- `Optimize-Windows.ps1` — all functions (grouped by `#region`), orchestration entry point guarded by dot-source detection.
- `catalog.json` — single source of truth for categories, items, and advanced entries.
- `tests/*.Tests.ps1` — Pester 5 tests that mock Windows cmdlets so they run cross-platform.
- `backups/` — created at runtime, contains timestamped CSVs + `Restore-*.ps1`.

---

## Tooling Prerequisite

The developer needs PowerShell 7+ on Linux (for local dev/tests) and Pester 5.
Install once:
```bash
# Arch Linux
sudo pacman -S powershell-bin
# Then in pwsh:
pwsh -c "Install-Module Pester -MinimumVersion 5.5.0 -Force -Scope CurrentUser"
```

---

## Task 1: Project scaffolding

**Files:**
- Create: `Optimize-Windows.ps1`
- Create: `catalog.json`
- Create: `.gitignore`
- Create: `README.md`
- Create: `tests/Catalog.Tests.ps1`

- [ ] **Step 1: Create `.gitignore`**

```
backups/
*.log
```

- [ ] **Step 2: Create skeleton `Optimize-Windows.ps1`**

```powershell
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
```

- [ ] **Step 3: Create empty valid `catalog.json`**

```json
{
  "version": "1.0",
  "minWindowsBuild": 22621,
  "categories": [],
  "advanced": []
}
```

- [ ] **Step 4: Create `README.md`**

```markdown
# Windows Services Optimizer

Script PowerShell interactif pour alleger Windows 11 (build >= 22621).

## Utilisation

```powershell
# Mode simulation (aucune modification)
.\Optimize-Windows.ps1 -DryRun

# Mode reel (execution en admin obligatoire)
.\Optimize-Windows.ps1
```

## Avertissements

- Execute uniquement sur Windows 11 22H2+.
- Cree automatiquement un point de restauration + des sauvegardes CSV.
- Les paquets AppX desinstalles ne peuvent etre restaures que manuellement via le Microsoft Store.

## Voir aussi

- `docs/superpowers/specs/2026-04-21-windows-services-optimizer-design.md` — design complet.
```

- [ ] **Step 5: Create empty test file `tests/Catalog.Tests.ps1`**

```powershell
BeforeAll {
    . "$PSScriptRoot/../Optimize-Windows.ps1"
}

Describe 'Catalog validation' {
    It 'placeholder' {
        $true | Should -Be $true
    }
}
```

- [ ] **Step 6: Run Pester to verify scaffolding works**

Run: `pwsh -c "Invoke-Pester -Path tests/"`
Expected: 1 test passes.

- [ ] **Step 7: Commit**

```bash
git add .gitignore Optimize-Windows.ps1 catalog.json README.md tests/
git commit -m "feat: scaffolding initial du projet

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Catalog loading & validation

**Files:**
- Modify: `Optimize-Windows.ps1` (add `Read-Catalog`, `Test-CatalogStructure`)
- Modify: `tests/Catalog.Tests.ps1`

- [ ] **Step 1: Write failing tests for `Test-CatalogStructure`**

Replace `tests/Catalog.Tests.ps1` body:

```powershell
BeforeAll {
    . "$PSScriptRoot/../Optimize-Windows.ps1"
}

Describe 'Test-CatalogStructure' {
    It 'accepts a minimal valid catalog' {
        $cat = [pscustomobject]@{
            version = '1.0'
            minWindowsBuild = 22621
            categories = @()
            advanced = @()
        }
        { Test-CatalogStructure -Catalog $cat } | Should -Not -Throw
    }

    It 'rejects a catalog missing version' {
        $cat = [pscustomobject]@{ minWindowsBuild = 22621; categories = @(); advanced = @() }
        { Test-CatalogStructure -Catalog $cat } | Should -Throw -ExpectedMessage '*version*'
    }

    It 'rejects a category with unknown item type' {
        $cat = [pscustomobject]@{
            version = '1.0'; minWindowsBuild = 22621; advanced = @()
            categories = @(
                [pscustomobject]@{
                    id = 'x'; question = 'q'; keepIfYes = $true
                    items = @([pscustomobject]@{ type = 'invalid'; name = 'X' })
                }
            )
        }
        { Test-CatalogStructure -Catalog $cat } | Should -Throw -ExpectedMessage '*type*'
    }

    It 'rejects a service item whose name is in the protected list' {
        $cat = [pscustomobject]@{
            version = '1.0'; minWindowsBuild = 22621; advanced = @()
            categories = @(
                [pscustomobject]@{
                    id = 'x'; question = 'q'; keepIfYes = $true
                    items = @([pscustomobject]@{ type = 'service'; name = 'WinDefend' })
                }
            )
        }
        { Test-CatalogStructure -Catalog $cat } | Should -Throw -ExpectedMessage '*protege*'
    }
}

Describe 'Read-Catalog' {
    It 'loads and parses the real catalog.json' {
        $path = Join-Path $PSScriptRoot '..' 'catalog.json'
        $cat = Read-Catalog -Path $path
        $cat.version | Should -Be '1.0'
    }

    It 'throws on missing file' {
        { Read-Catalog -Path '/nonexistent/path.json' } | Should -Throw
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -c "Invoke-Pester -Path tests/Catalog.Tests.ps1"`
Expected: FAIL with "Test-CatalogStructure not recognized" or similar.

- [ ] **Step 3: Implement the functions**

Insert inside the `#region Functions` block of `Optimize-Windows.ps1`:

```powershell
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -c "Invoke-Pester -Path tests/Catalog.Tests.ps1"`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Optimize-Windows.ps1 tests/Catalog.Tests.ps1
git commit -m "feat: chargement et validation du catalogue JSON

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Environment checks (admin + Windows build)

**Files:**
- Modify: `Optimize-Windows.ps1` (add `Test-IsElevated`, `Test-WindowsCompatible`)
- Create: `tests/Environment.Tests.ps1`

- [ ] **Step 1: Write failing tests**

Create `tests/Environment.Tests.ps1`:

```powershell
BeforeAll {
    . "$PSScriptRoot/../Optimize-Windows.ps1"
}

Describe 'Test-WindowsCompatible' {
    It 'returns true for build >= 22621' {
        Test-WindowsCompatible -CurrentBuild 22621 -MinBuild 22621 | Should -BeTrue
        Test-WindowsCompatible -CurrentBuild 26100 -MinBuild 22621 | Should -BeTrue
    }
    It 'returns false for build < 22621' {
        Test-WindowsCompatible -CurrentBuild 22000 -MinBuild 22621 | Should -BeFalse
        Test-WindowsCompatible -CurrentBuild 19045 -MinBuild 22621 | Should -BeFalse
    }
}

Describe 'Get-CurrentWindowsBuild' {
    It 'returns an integer' {
        # On non-Windows systems this may return 0 - test just checks return type contract
        $result = Get-CurrentWindowsBuild
        $result | Should -BeOfType [int]
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -c "Invoke-Pester -Path tests/Environment.Tests.ps1"`
Expected: FAIL — functions not defined.

- [ ] **Step 3: Implement the functions**

Add inside `#region Functions`:

```powershell
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -c "Invoke-Pester -Path tests/Environment.Tests.ps1"`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Optimize-Windows.ps1 tests/Environment.Tests.ps1
git commit -m "feat: verifications environnement (admin + build Windows)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: UI helpers (colored prompts + Yes/No/Skip)

**Files:**
- Modify: `Optimize-Windows.ps1` (add `Write-Info`, `Read-YesNoSkip`)
- Create: `tests/UI.Tests.ps1`

- [ ] **Step 1: Write failing tests**

Create `tests/UI.Tests.ps1`:

```powershell
BeforeAll {
    . "$PSScriptRoot/../Optimize-Windows.ps1"
}

Describe 'Read-YesNoSkip' {
    It 'returns "yes" for O / o / Y / y' {
        Mock -CommandName Read-Host -MockWith { 'O' }
        Read-YesNoSkip -Prompt 'Q?' | Should -Be 'yes'
        Mock -CommandName Read-Host -MockWith { 'y' }
        Read-YesNoSkip -Prompt 'Q?' | Should -Be 'yes'
    }
    It 'returns "no" for N / n' {
        Mock -CommandName Read-Host -MockWith { 'N' }
        Read-YesNoSkip -Prompt 'Q?' | Should -Be 'no'
    }
    It 'returns "skip" for S / s' {
        Mock -CommandName Read-Host -MockWith { 's' }
        Read-YesNoSkip -Prompt 'Q?' | Should -Be 'skip'
    }
    It 'retries on invalid input then accepts valid' {
        $script:answers = @('zzz','O')
        $script:idx = 0
        Mock -CommandName Read-Host -MockWith {
            $a = $script:answers[$script:idx]; $script:idx++; return $a
        }
        Read-YesNoSkip -Prompt 'Q?' | Should -Be 'yes'
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -c "Invoke-Pester -Path tests/UI.Tests.ps1"`
Expected: FAIL — `Read-YesNoSkip` not found.

- [ ] **Step 3: Implement the functions**

Add inside `#region Functions`:

```powershell
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
        $answer = (Read-Host -Prompt "$Prompt [O/N/S]").Trim().ToLowerInvariant()
        switch ($answer) {
            { $_ -in 'o','y','oui','yes' } { return 'yes' }
            { $_ -in 'n','non','no' }      { return 'no' }
            { $_ -in 's','skip' }          { return 'skip' }
            ''                             { return $Default }
            default {
                Write-Warn "Reponse invalide. Tapez O, N ou S."
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -c "Invoke-Pester -Path tests/UI.Tests.ps1"`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Optimize-Windows.ps1 tests/UI.Tests.ps1
git commit -m "feat: helpers UI console (prompts O/N/S et sortie coloree)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: State snapshots (CSV exports)

**Files:**
- Modify: `Optimize-Windows.ps1` (add `Export-StateSnapshot`, `New-BackupDirectory`)
- Create: `tests/Backup.Tests.ps1`

- [ ] **Step 1: Write failing tests**

Create `tests/Backup.Tests.ps1`:

```powershell
BeforeAll {
    . "$PSScriptRoot/../Optimize-Windows.ps1"
}

Describe 'New-BackupDirectory' {
    It 'creates a timestamped subdirectory under the given root' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "wsopt-test-$(Get-Random)"
        try {
            $dir = New-BackupDirectory -Root $tempRoot
            Test-Path -LiteralPath $dir | Should -BeTrue
            (Split-Path -Path $dir -Parent) | Should -Be $tempRoot
            (Split-Path -Path $dir -Leaf) | Should -Match '^\d{8}-\d{6}$'
        } finally {
            if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
        }
    }
}

Describe 'Export-StateSnapshot (services)' {
    It 'writes a CSV with expected columns for the given service names' {
        Mock -CommandName Get-Service -MockWith {
            param($Name)
            [pscustomobject]@{
                Name = $Name; DisplayName = "Disp $Name"; Status = 'Running'; StartType = 'Automatic'
            }
        }
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "wsopt-$(Get-Random)"
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        try {
            Export-StateSnapshot -Type service -Names @('Spooler','Fax') -OutputDir $tempDir
            $csvPath = Join-Path $tempDir 'services.csv'
            Test-Path $csvPath | Should -BeTrue
            $rows = Import-Csv $csvPath
            $rows.Count | Should -Be 2
            $rows[0].Name | Should -Be 'Spooler'
            $rows[0].StartType | Should -Be 'Automatic'
        } finally {
            Remove-Item $tempDir -Recurse -Force
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -c "Invoke-Pester -Path tests/Backup.Tests.ps1"`
Expected: FAIL — functions not defined.

- [ ] **Step 3: Implement the functions**

Add inside `#region Functions`:

```powershell
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
                } catch { } # service absent : ignore
            }
        }
        'task' {
            foreach ($n in $Names) {
                $path = Split-Path $n -Parent
                $leaf = Split-Path $n -Leaf
                try {
                    $t = Get-ScheduledTask -TaskPath "$path\" -TaskName $leaf -ErrorAction Stop
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
        # Ecrit au moins les en-tetes pour audit
        Set-Content -LiteralPath $outPath -Value '' -Encoding UTF8
    }
    return $outPath
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -c "Invoke-Pester -Path tests/Backup.Tests.ps1"`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Optimize-Windows.ps1 tests/Backup.Tests.ps1
git commit -m "feat: snapshots CSV de l'etat initial (services/tasks/features/appx)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Restore point creation

**Files:**
- Modify: `Optimize-Windows.ps1` (add `New-SystemRestorePoint`)
- Modify: `tests/Backup.Tests.ps1`

- [ ] **Step 1: Append failing tests to `tests/Backup.Tests.ps1`**

```powershell
Describe 'New-SystemRestorePoint' {
    It 'returns $true when Checkpoint-Computer succeeds' {
        Mock -CommandName Enable-ComputerRestore -MockWith { }
        Mock -CommandName Checkpoint-Computer -MockWith { }
        New-SystemRestorePoint -Description 'test' | Should -BeTrue
    }

    It 'returns $false and warns when Checkpoint-Computer throws' {
        Mock -CommandName Enable-ComputerRestore -MockWith { }
        Mock -CommandName Checkpoint-Computer -MockWith { throw 'limit 24h' }
        Mock -CommandName Write-Warning -MockWith { }
        New-SystemRestorePoint -Description 'test' | Should -BeFalse
        Should -Invoke Write-Warning -Times 1
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -c "Invoke-Pester -Path tests/Backup.Tests.ps1"`
Expected: FAIL — `New-SystemRestorePoint` not found.

- [ ] **Step 3: Implement the function**

Add inside `#region Functions`:

```powershell
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -c "Invoke-Pester -Path tests/Backup.Tests.ps1"`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Optimize-Windows.ps1 tests/Backup.Tests.ps1
git commit -m "feat: creation du point de restauration systeme avec fallback

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Service handler (Disable + Restore-append)

**Files:**
- Modify: `Optimize-Windows.ps1` (add `Disable-ServiceItem`, `Add-RestoreCommand`)
- Create: `tests/Handlers.Tests.ps1`

- [ ] **Step 1: Write failing tests**

Create `tests/Handlers.Tests.ps1`:

```powershell
BeforeAll {
    . "$PSScriptRoot/../Optimize-Windows.ps1"
}

Describe 'Add-RestoreCommand' {
    It 'appends the command to the restore script with a trailing newline' {
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            Add-RestoreCommand -Path $tmp -Command "Set-Service -Name 'Spooler' -StartupType Automatic"
            Add-RestoreCommand -Path $tmp -Command "Start-Service -Name 'Spooler'"
            $content = Get-Content -LiteralPath $tmp -Raw
            $content | Should -Match "Set-Service -Name 'Spooler' -StartupType Automatic"
            $content | Should -Match "Start-Service -Name 'Spooler'"
        } finally {
            Remove-Item $tmp -Force
        }
    }
}

Describe 'Disable-ServiceItem' {
    It 'stops and disables the service and appends restore commands' {
        Mock -CommandName Get-Service -MockWith {
            [pscustomobject]@{ Name='Spooler'; Status='Running'; StartType='Automatic' }
        }
        Mock -CommandName Stop-Service -MockWith { }
        Mock -CommandName Set-Service -MockWith { }
        $tmpRestore = [System.IO.Path]::GetTempFileName()
        try {
            $result = Disable-ServiceItem -Name 'Spooler' -RestoreScriptPath $tmpRestore -DryRun:$false
            $result.Success | Should -BeTrue
            Should -Invoke Stop-Service -Times 1 -ParameterFilter { $Name -eq 'Spooler' }
            Should -Invoke Set-Service -Times 1 -ParameterFilter { $Name -eq 'Spooler' -and $StartupType -eq 'Disabled' }
            (Get-Content $tmpRestore -Raw) | Should -Match "Set-Service -Name 'Spooler' -StartupType Automatic"
            (Get-Content $tmpRestore -Raw) | Should -Match "Start-Service -Name 'Spooler'"
        } finally {
            Remove-Item $tmpRestore -Force
        }
    }

    It 'refuses to disable a protected service' {
        $tmpRestore = [System.IO.Path]::GetTempFileName()
        try {
            { Disable-ServiceItem -Name 'WinDefend' -RestoreScriptPath $tmpRestore -DryRun:$false } |
                Should -Throw -ExpectedMessage '*protege*'
        } finally {
            Remove-Item $tmpRestore -Force
        }
    }

    It 'does nothing (but logs) when DryRun is set' {
        Mock -CommandName Get-Service -MockWith {
            [pscustomobject]@{ Name='Spooler'; Status='Running'; StartType='Automatic' }
        }
        Mock -CommandName Stop-Service -MockWith { }
        Mock -CommandName Set-Service -MockWith { }
        $tmpRestore = [System.IO.Path]::GetTempFileName()
        try {
            $result = Disable-ServiceItem -Name 'Spooler' -RestoreScriptPath $tmpRestore -DryRun:$true
            $result.Success | Should -BeTrue
            Should -Invoke Stop-Service -Times 0
            Should -Invoke Set-Service -Times 0
        } finally {
            Remove-Item $tmpRestore -Force
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -c "Invoke-Pester -Path tests/Handlers.Tests.ps1"`
Expected: FAIL — functions not found.

- [ ] **Step 3: Implement the functions**

Add inside `#region Functions`:

```powershell
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -c "Invoke-Pester -Path tests/Handlers.Tests.ps1"`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Optimize-Windows.ps1 tests/Handlers.Tests.ps1
git commit -m "feat: handler service (desactivation + append restore)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: ScheduledTask handler

**Files:**
- Modify: `Optimize-Windows.ps1` (add `Disable-TaskItem`)
- Modify: `tests/Handlers.Tests.ps1`

- [ ] **Step 1: Append failing tests**

```powershell
Describe 'Disable-TaskItem' {
    It 'disables a scheduled task and appends the enable command to restore' {
        Mock -CommandName Get-ScheduledTask -MockWith {
            [pscustomobject]@{ TaskPath='\Microsoft\Windows\App\'; TaskName='Foo'; State='Ready' }
        }
        Mock -CommandName Disable-ScheduledTask -MockWith { }
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            $r = Disable-TaskItem -FullPath '\Microsoft\Windows\App\Foo' -RestoreScriptPath $tmp -DryRun:$false
            $r.Success | Should -BeTrue
            Should -Invoke Disable-ScheduledTask -Times 1
            (Get-Content $tmp -Raw) | Should -Match "Enable-ScheduledTask -TaskPath '\\\\Microsoft\\\\Windows\\\\App\\\\' -TaskName 'Foo'"
        } finally {
            Remove-Item $tmp -Force
        }
    }

    It 'returns failure when task not found' {
        Mock -CommandName Get-ScheduledTask -MockWith { throw 'not found' }
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            $r = Disable-TaskItem -FullPath '\Missing\Task' -RestoreScriptPath $tmp -DryRun:$false
            $r.Success | Should -BeFalse
        } finally {
            Remove-Item $tmp -Force
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -c "Invoke-Pester -Path tests/Handlers.Tests.ps1"`
Expected: FAIL — `Disable-TaskItem` not found.

- [ ] **Step 3: Implement the function**

Add inside `#region Functions`:

```powershell
function Disable-TaskItem {
    param(
        [Parameter(Mandatory)][string] $FullPath,
        [Parameter(Mandatory)][string] $RestoreScriptPath,
        [switch] $DryRun
    )
    $parent = Split-Path $FullPath -Parent
    $leaf   = Split-Path $FullPath -Leaf
    $taskPath = if ($parent.EndsWith('\')) { $parent } else { "$parent\" }

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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -c "Invoke-Pester -Path tests/Handlers.Tests.ps1"`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Optimize-Windows.ps1 tests/Handlers.Tests.ps1
git commit -m "feat: handler tache planifiee

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Feature handler

**Files:**
- Modify: `Optimize-Windows.ps1` (add `Disable-FeatureItem`)
- Modify: `tests/Handlers.Tests.ps1`

- [ ] **Step 1: Append failing tests**

```powershell
Describe 'Disable-FeatureItem' {
    It 'disables an enabled feature and appends enable command to restore' {
        Mock -CommandName Get-WindowsOptionalFeature -MockWith {
            [pscustomobject]@{ FeatureName='IE'; State='Enabled' }
        }
        Mock -CommandName Disable-WindowsOptionalFeature -MockWith { }
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            $r = Disable-FeatureItem -Name 'IE' -RestoreScriptPath $tmp -DryRun:$false
            $r.Success | Should -BeTrue
            (Get-Content $tmp -Raw) | Should -Match "Enable-WindowsOptionalFeature -Online -FeatureName 'IE' -NoRestart"
        } finally { Remove-Item $tmp -Force }
    }

    It 'returns success without action when feature already disabled' {
        Mock -CommandName Get-WindowsOptionalFeature -MockWith {
            [pscustomobject]@{ FeatureName='IE'; State='Disabled' }
        }
        Mock -CommandName Disable-WindowsOptionalFeature -MockWith { }
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            $r = Disable-FeatureItem -Name 'IE' -RestoreScriptPath $tmp -DryRun:$false
            $r.Success | Should -BeTrue
            Should -Invoke Disable-WindowsOptionalFeature -Times 0
        } finally { Remove-Item $tmp -Force }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -c "Invoke-Pester -Path tests/Handlers.Tests.ps1"`
Expected: FAIL.

- [ ] **Step 3: Implement the function**

Add inside `#region Functions`:

```powershell
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -c "Invoke-Pester -Path tests/Handlers.Tests.ps1"`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Optimize-Windows.ps1 tests/Handlers.Tests.ps1
git commit -m "feat: handler fonctionnalite optionnelle

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: AppX handler (with documentation-only restore)

**Files:**
- Modify: `Optimize-Windows.ps1` (add `Remove-AppxItem`)
- Modify: `tests/Handlers.Tests.ps1`

- [ ] **Step 1: Append failing tests**

```powershell
Describe 'Remove-AppxItem' {
    It 'removes the AppX package and appends a commented restore line' {
        Mock -CommandName Get-AppxPackage -MockWith {
            [pscustomobject]@{
                Name='Microsoft.XboxGamingOverlay'
                PackageFullName='Microsoft.XboxGamingOverlay_5.823.1271.0_x64__8wekyb3d8bbwa'
                Publisher='CN=Microsoft Corporation'
            }
        }
        Mock -CommandName Remove-AppxPackage -MockWith { }
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            $r = Remove-AppxItem -Name 'Microsoft.XboxGamingOverlay' -RestoreScriptPath $tmp -DryRun:$false
            $r.Success | Should -BeTrue
            (Get-Content $tmp -Raw) | Should -Match '# Microsoft.XboxGamingOverlay'
            (Get-Content $tmp -Raw) | Should -Match 'reinstaller via Microsoft Store'
        } finally { Remove-Item $tmp -Force }
    }

    It 'returns success without action when package not installed' {
        Mock -CommandName Get-AppxPackage -MockWith { $null }
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            $r = Remove-AppxItem -Name 'NotInstalled' -RestoreScriptPath $tmp -DryRun:$false
            $r.Success | Should -BeTrue
            $r.Reason | Should -Match 'absent'
        } finally { Remove-Item $tmp -Force }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -c "Invoke-Pester -Path tests/Handlers.Tests.ps1"`
Expected: FAIL.

- [ ] **Step 3: Implement the function**

Add inside `#region Functions`:

```powershell
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -c "Invoke-Pester -Path tests/Handlers.Tests.ps1"`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Optimize-Windows.ps1 tests/Handlers.Tests.ps1
git commit -m "feat: handler AppX (desinstallation + rappel store pour rollback)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: Handler dispatch (`Invoke-ItemAction`)

**Files:**
- Modify: `Optimize-Windows.ps1` (add `Invoke-ItemAction`)
- Modify: `tests/Handlers.Tests.ps1`

- [ ] **Step 1: Append failing tests**

```powershell
Describe 'Invoke-ItemAction dispatch' {
    BeforeEach {
        $script:called = $null
        Mock -CommandName Disable-ServiceItem -MockWith { $script:called = 'service' ; [pscustomobject]@{ Success=$true; Reason='OK' } }
        Mock -CommandName Disable-TaskItem    -MockWith { $script:called = 'task'    ; [pscustomobject]@{ Success=$true; Reason='OK' } }
        Mock -CommandName Disable-FeatureItem -MockWith { $script:called = 'feature' ; [pscustomobject]@{ Success=$true; Reason='OK' } }
        Mock -CommandName Remove-AppxItem     -MockWith { $script:called = 'appx'    ; [pscustomobject]@{ Success=$true; Reason='OK' } }
    }

    It 'dispatches a service item to Disable-ServiceItem' {
        Invoke-ItemAction -Item ([pscustomobject]@{ type='service'; name='X' }) -RestoreScriptPath 'x.ps1' -DryRun:$false
        $script:called | Should -Be 'service'
    }
    It 'dispatches a task item to Disable-TaskItem' {
        Invoke-ItemAction -Item ([pscustomobject]@{ type='task'; name='\a\b' }) -RestoreScriptPath 'x.ps1' -DryRun:$false
        $script:called | Should -Be 'task'
    }
    It 'dispatches a feature item to Disable-FeatureItem' {
        Invoke-ItemAction -Item ([pscustomobject]@{ type='feature'; name='IE' }) -RestoreScriptPath 'x.ps1' -DryRun:$false
        $script:called | Should -Be 'feature'
    }
    It 'dispatches an appx item to Remove-AppxItem' {
        Invoke-ItemAction -Item ([pscustomobject]@{ type='appx'; name='Foo' }) -RestoreScriptPath 'x.ps1' -DryRun:$false
        $script:called | Should -Be 'appx'
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -c "Invoke-Pester -Path tests/Handlers.Tests.ps1"`
Expected: FAIL.

- [ ] **Step 3: Implement the function**

Add inside `#region Functions`:

```powershell
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -c "Invoke-Pester -Path tests/Handlers.Tests.ps1"`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Optimize-Windows.ps1 tests/Handlers.Tests.ps1
git commit -m "feat: dispatch generique d'item vers le bon handler

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 12: Decision collection (`Invoke-CategoryPhase`, `Invoke-AdvancedPhase`)

**Files:**
- Modify: `Optimize-Windows.ps1`
- Create: `tests/Orchestration.Tests.ps1`

- [ ] **Step 1: Write failing tests**

Create `tests/Orchestration.Tests.ps1`:

```powershell
BeforeAll {
    . "$PSScriptRoot/../Optimize-Windows.ps1"
}

Describe 'Invoke-CategoryPhase' {
    It 'marks items DISABLE when keepIfYes=true and user answers No' {
        Mock -CommandName Read-YesNoSkip -MockWith { 'no' }
        $catalog = [pscustomobject]@{
            categories = @(
                [pscustomobject]@{
                    id='printing'; question='Imprimante ?'; keepIfYes=$true
                    items=@([pscustomobject]@{ type='service'; name='Spooler' })
                }
            )
        }
        $decisions = Invoke-CategoryPhase -Catalog $catalog
        $decisions.Count | Should -Be 1
        $decisions[0].name | Should -Be 'Spooler'
    }

    It 'marks items KEEP (empty decisions) when keepIfYes=true and user answers Yes' {
        Mock -CommandName Read-YesNoSkip -MockWith { 'yes' }
        $catalog = [pscustomobject]@{
            categories = @(
                [pscustomobject]@{
                    id='printing'; question='Imprimante ?'; keepIfYes=$true
                    items=@([pscustomobject]@{ type='service'; name='Spooler' })
                }
            )
        }
        (Invoke-CategoryPhase -Catalog $catalog).Count | Should -Be 0
    }

    It 'marks items DISABLE when keepIfYes=false and user answers Yes (inverted)' {
        Mock -CommandName Read-YesNoSkip -MockWith { 'yes' }
        $catalog = [pscustomobject]@{
            categories = @(
                [pscustomobject]@{
                    id='telemetry'; question='Desactiver telemetrie ?'; keepIfYes=$false
                    items=@([pscustomobject]@{ type='service'; name='DiagTrack' })
                }
            )
        }
        (Invoke-CategoryPhase -Catalog $catalog)[0].name | Should -Be 'DiagTrack'
    }

    It 'produces no decisions when user skips the category' {
        Mock -CommandName Read-YesNoSkip -MockWith { 'skip' }
        $catalog = [pscustomobject]@{
            categories = @(
                [pscustomobject]@{
                    id='x'; question='q'; keepIfYes=$true
                    items=@([pscustomobject]@{ type='service'; name='Spooler' })
                }
            )
        }
        (Invoke-CategoryPhase -Catalog $catalog).Count | Should -Be 0
    }
}

Describe 'Invoke-AdvancedPhase' {
    It 'asks per item and collects yes answers' {
        $script:answers = @('yes','no'); $script:idx = 0
        Mock -CommandName Read-YesNoSkip -MockWith {
            $a = $script:answers[$script:idx]; $script:idx++; $a
        }
        $catalog = [pscustomobject]@{
            advanced = @(
                [pscustomobject]@{ type='service'; name='Fax';         description='Service de fax' },
                [pscustomobject]@{ type='service'; name='MapsBroker';  description='Cartes hors ligne' }
            )
        }
        $decisions = Invoke-AdvancedPhase -Catalog $catalog
        $decisions.Count | Should -Be 1
        $decisions[0].name | Should -Be 'Fax'
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -c "Invoke-Pester -Path tests/Orchestration.Tests.ps1"`
Expected: FAIL.

- [ ] **Step 3: Implement the functions**

Add inside `#region Functions`:

```powershell
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
    return $decisions
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
    return $decisions
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -c "Invoke-Pester -Path tests/Orchestration.Tests.ps1"`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Optimize-Windows.ps1 tests/Orchestration.Tests.ps1
git commit -m "feat: phases interactives (categories + avancee)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 13: Restore script header initialization

**Files:**
- Modify: `Optimize-Windows.ps1` (add `Initialize-RestoreScript`)
- Modify: `tests/Handlers.Tests.ps1`

- [ ] **Step 1: Append failing tests**

```powershell
Describe 'Initialize-RestoreScript' {
    It 'creates a file with the expected header' {
        $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "wsopt-$(Get-Random)"
        New-Item -ItemType Directory -Path $tmpDir | Out-Null
        try {
            $p = Initialize-RestoreScript -BackupDir $tmpDir
            Test-Path $p | Should -BeTrue
            (Get-Content $p -Raw) | Should -Match '#Requires -RunAsAdministrator'
            (Get-Content $p -Raw) | Should -Match 'Script de restauration'
        } finally {
            Remove-Item $tmpDir -Recurse -Force
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -c "Invoke-Pester -Path tests/Handlers.Tests.ps1"`
Expected: FAIL.

- [ ] **Step 3: Implement the function**

Add inside `#region Functions`:

```powershell
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -c "Invoke-Pester -Path tests/Handlers.Tests.ps1"`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Optimize-Windows.ps1 tests/Handlers.Tests.ps1
git commit -m "feat: initialisation de l'entete du script de restauration

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 14: Summary display + final confirmation

**Files:**
- Modify: `Optimize-Windows.ps1` (add `Show-Summary`, `Read-FinalConfirmation`)
- Modify: `tests/Orchestration.Tests.ps1`

- [ ] **Step 1: Append failing tests**

```powershell
Describe 'Show-Summary' {
    It 'counts decisions by type' {
        $decisions = @(
            [pscustomobject]@{ type='service'; name='Spooler' },
            [pscustomobject]@{ type='service'; name='Fax' },
            [pscustomobject]@{ type='task';    name='\a\b' },
            [pscustomobject]@{ type='appx';    name='Foo' }
        )
        $summary = Get-SummaryCounts -Decisions $decisions
        $summary.service | Should -Be 2
        $summary.task    | Should -Be 1
        $summary.feature | Should -Be 0
        $summary.appx    | Should -Be 1
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -c "Invoke-Pester -Path tests/Orchestration.Tests.ps1"`
Expected: FAIL.

- [ ] **Step 3: Implement the functions**

Add inside `#region Functions`:

```powershell
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -c "Invoke-Pester -Path tests/Orchestration.Tests.ps1"`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Optimize-Windows.ps1 tests/Orchestration.Tests.ps1
git commit -m "feat: recapitulatif des decisions et confirmation finale

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 15: Main orchestration (`Invoke-Optimization`)

**Files:**
- Modify: `Optimize-Windows.ps1` (add `Invoke-Optimization`, wire into main guard)
- Modify: `tests/Orchestration.Tests.ps1`

- [ ] **Step 1: Append failing tests**

```powershell
Describe 'Invoke-Optimization end-to-end (DryRun)' {
    It 'runs through the flow without modifications when DryRun is set' {
        # Prepare a tiny valid catalog on disk
        $tmpRoot = Join-Path ([System.IO.Path]::GetTempPath()) "wsopt-e2e-$(Get-Random)"
        New-Item -ItemType Directory -Path $tmpRoot | Out-Null
        $catalogPath = Join-Path $tmpRoot 'catalog.json'
        $backupRoot  = Join-Path $tmpRoot 'backups'
        @{
            version = '1.0'
            minWindowsBuild = 22621
            categories = @(@{
                id = 'printing'; question = 'Imprimante ?'; keepIfYes = $true
                items = @(@{ type = 'service'; name = 'Spooler' })
            })
            advanced = @()
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $catalogPath -Encoding UTF8

        Mock -CommandName Test-IsElevated -MockWith { $true }
        Mock -CommandName Get-CurrentWindowsBuild -MockWith { 22621 }
        Mock -CommandName Read-YesNoSkip -MockWith { 'yes' }   # consent + all questions
        Mock -CommandName Get-Service -MockWith {
            [pscustomobject]@{ Name='Spooler'; DisplayName='Print Spooler'; Status='Running'; StartType='Automatic' }
        }
        Mock -CommandName Enable-ComputerRestore -MockWith { }
        Mock -CommandName Checkpoint-Computer -MockWith { }

        try {
            $result = Invoke-Optimization -CatalogPath $catalogPath -BackupRoot $backupRoot -DryRun
            $result.ExitCode | Should -Be 0
            Test-Path $backupRoot | Should -BeTrue
            # services.csv created in backup dir
            Get-ChildItem -Path $backupRoot -Recurse -Filter 'services.csv' | Should -Not -BeNullOrEmpty
        } finally {
            Remove-Item $tmpRoot -Recurse -Force
        }
    }

    It 'aborts early when not elevated' {
        Mock -CommandName Test-IsElevated -MockWith { $false }
        $r = Invoke-Optimization -CatalogPath 'x' -BackupRoot 'y' -DryRun
        $r.ExitCode | Should -Be 1
    }

    It 'aborts early when Windows build is below the minimum' {
        Mock -CommandName Test-IsElevated -MockWith { $true }
        Mock -CommandName Get-CurrentWindowsBuild -MockWith { 19045 }
        $r = Invoke-Optimization -CatalogPath 'x' -BackupRoot 'y' -DryRun
        $r.ExitCode | Should -Be 2
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -c "Invoke-Pester -Path tests/Orchestration.Tests.ps1"`
Expected: FAIL.

- [ ] **Step 3: Implement the function**

Add inside `#region Functions`:

```powershell
function Invoke-Optimization {
    param(
        [Parameter(Mandatory)][string] $CatalogPath,
        [Parameter(Mandatory)][string] $BackupRoot,
        [switch] $DryRun
    )

    # 1. Environment checks
    if (-not (Test-IsElevated)) {
        Write-Danger 'Execution administrateur requise.'
        return [pscustomobject]@{ ExitCode = 1 }
    }
    $build = Get-CurrentWindowsBuild
    if (-not (Test-WindowsCompatible -CurrentBuild $build -MinBuild $script:MinWindowsBuild)) {
        Write-Danger "Windows build $build < $($script:MinWindowsBuild) (22H2). Abort."
        return [pscustomobject]@{ ExitCode = 2 }
    }

    # 2. Catalog
    $catalog = Read-Catalog -Path $CatalogPath
    Test-CatalogStructure -Catalog $catalog

    # 3. Initial consent
    Write-Warn 'Cet outil va desactiver des composants Windows selon tes reponses.'
    Write-Warn 'Un point de restauration et des CSV de sauvegarde seront crees.'
    if (-not $DryRun) {
        if ((Read-YesNoSkip -Prompt 'Continuer ?') -ne 'yes') {
            return [pscustomobject]@{ ExitCode = 3 }
        }
    }

    # 4. Backup directory
    $backupDir = New-BackupDirectory -Root $BackupRoot
    $restoreScript = Initialize-RestoreScript -BackupDir $backupDir

    # 5. Build list of all item names by type for pre-snapshot
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

    # 6. Restore point (skippable if 24h limit hit)
    if (-not $DryRun) {
        New-SystemRestorePoint -Description 'Pre-Optimize-Windows' | Out-Null
    }

    # 7. Decisions
    $decisions = @()
    $decisions += Invoke-CategoryPhase -Catalog $catalog
    $decisions += Invoke-AdvancedPhase -Catalog $catalog

    # 8. Summary + final confirmation
    Show-Summary -Decisions $decisions -DryRun:$DryRun
    if (-not (Read-FinalConfirmation -DryRun:$DryRun)) {
        Write-Warn 'Annule par l utilisateur.'
        return [pscustomobject]@{ ExitCode = 4 }
    }

    # 9. Apply
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
```

- [ ] **Step 4: Wire the main guard to call `Invoke-Optimization`**

Replace the existing `#region Main` block in `Optimize-Windows.ps1` with:

```powershell
#region Main
if ($MyInvocation.InvocationName -ne '.') {
    $result = Invoke-Optimization -CatalogPath $CatalogPath -BackupRoot $BackupRoot -DryRun:$DryRun
    exit $result.ExitCode
}
#endregion
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `pwsh -c "Invoke-Pester -Path tests/"`
Expected: All tests PASS (full suite).

- [ ] **Step 6: Commit**

```bash
git add Optimize-Windows.ps1 tests/Orchestration.Tests.ps1
git commit -m "feat: orchestration complete Invoke-Optimization + mode DryRun

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 16: Populate the full catalog

**Files:**
- Modify: `catalog.json`

- [ ] **Step 1: Replace `catalog.json` with the full 14 categories + advanced items**

```json
{
  "version": "1.0",
  "minWindowsBuild": 22621,
  "categories": [
    {
      "id": "printing",
      "question": "Utilises-tu une imprimante (locale ou reseau) ?",
      "keepIfYes": true,
      "items": [
        { "type": "service", "name": "Spooler", "description": "File d'impression" },
        { "type": "service", "name": "PrintNotify", "description": "Notifications imprimante" },
        { "type": "service", "name": "PrintWorkflowUserSvc", "description": "Workflow d'impression" },
        { "type": "task",    "name": "\\Microsoft\\Windows\\Printing\\EduPrintProv" }
      ]
    },
    {
      "id": "fax",
      "question": "Utilises-tu le fax ?",
      "keepIfYes": true,
      "items": [
        { "type": "service", "name": "Fax", "description": "Service de fax" }
      ]
    },
    {
      "id": "bluetooth",
      "question": "Utilises-tu le Bluetooth ?",
      "keepIfYes": true,
      "items": [
        { "type": "service", "name": "bthserv" },
        { "type": "service", "name": "BluetoothUserService" },
        { "type": "service", "name": "BTAGService" },
        { "type": "service", "name": "BthAvctpSvc" }
      ]
    },
    {
      "id": "xbox",
      "question": "Utilises-tu Xbox Game Bar / Xbox Live ?",
      "keepIfYes": true,
      "items": [
        { "type": "service", "name": "XblAuthManager" },
        { "type": "service", "name": "XblGameSave" },
        { "type": "service", "name": "XboxGipSvc" },
        { "type": "service", "name": "XboxNetApiSvc" },
        { "type": "appx",    "name": "Microsoft.XboxGamingOverlay" },
        { "type": "appx",    "name": "Microsoft.GamingApp" },
        { "type": "appx",    "name": "Microsoft.Xbox.TCUI" },
        { "type": "appx",    "name": "Microsoft.XboxSpeechToTextOverlay" }
      ]
    },
    {
      "id": "hyperv",
      "question": "Utilises-tu Hyper-V / machines virtuelles Windows ?",
      "keepIfYes": true,
      "items": [
        { "type": "service", "name": "vmcompute" },
        { "type": "service", "name": "vmms" },
        { "type": "service", "name": "HvHost" },
        { "type": "service", "name": "vmickvpexchange" },
        { "type": "service", "name": "vmicguestinterface" },
        { "type": "service", "name": "vmicshutdown" },
        { "type": "service", "name": "vmicheartbeat" },
        { "type": "service", "name": "vmicrdv" },
        { "type": "service", "name": "vmictimesync" },
        { "type": "service", "name": "vmicvmsession" },
        { "type": "feature", "name": "Microsoft-Hyper-V-All" }
      ]
    },
    {
      "id": "wsl",
      "question": "Utilises-tu WSL (Linux sous Windows) ?",
      "keepIfYes": true,
      "items": [
        { "type": "feature", "name": "Microsoft-Windows-Subsystem-Linux" },
        { "type": "feature", "name": "VirtualMachinePlatform" }
      ]
    },
    {
      "id": "rdp",
      "question": "Autorises-tu les connexions Bureau a distance entrantes ?",
      "keepIfYes": true,
      "items": [
        { "type": "service", "name": "TermService" },
        { "type": "service", "name": "SessionEnv" },
        { "type": "service", "name": "UmRdpService" }
      ]
    },
    {
      "id": "smb",
      "question": "Partages-tu des fichiers/imprimantes en reseau (SMB) ?",
      "keepIfYes": true,
      "items": [
        { "type": "service", "name": "LanmanServer" },
        { "type": "service", "name": "Browser" }
      ]
    },
    {
      "id": "location",
      "question": "Utilises-tu les services de localisation (GPS) ?",
      "keepIfYes": true,
      "items": [
        { "type": "service", "name": "lfsvc" }
      ]
    },
    {
      "id": "biometrics",
      "question": "Utilises-tu Windows Hello (biometrie) ?",
      "keepIfYes": true,
      "items": [
        { "type": "service", "name": "WbioSrvc" }
      ]
    },
    {
      "id": "touch",
      "question": "Ton PC a-t-il un ecran tactile ou utilises-tu l'ecriture manuscrite ?",
      "keepIfYes": true,
      "items": [
        { "type": "service", "name": "TabletInputService" },
        { "type": "service", "name": "TextInputManagementService" }
      ]
    },
    {
      "id": "onedrive",
      "question": "Utilises-tu OneDrive ?",
      "keepIfYes": true,
      "items": [
        { "type": "appx", "name": "Microsoft.OneDriveSync" }
      ]
    },
    {
      "id": "cortana",
      "question": "Utilises-tu Cortana / la recherche Bing dans Windows ?",
      "keepIfYes": true,
      "items": [
        { "type": "appx", "name": "Microsoft.549981C3F5F10" }
      ]
    },
    {
      "id": "telemetry",
      "question": "Desactiver la telemetrie et les diagnostics Microsoft (recommande) ?",
      "keepIfYes": false,
      "items": [
        { "type": "service", "name": "DiagTrack" },
        { "type": "service", "name": "dmwappushservice" },
        { "type": "service", "name": "WerSvc" },
        { "type": "service", "name": "PcaSvc" },
        { "type": "service", "name": "WdiServiceHost" },
        { "type": "service", "name": "WdiSystemHost" },
        { "type": "task", "name": "\\Microsoft\\Windows\\Application Experience\\Microsoft Compatibility Appraiser" },
        { "type": "task", "name": "\\Microsoft\\Windows\\Application Experience\\ProgramDataUpdater" },
        { "type": "task", "name": "\\Microsoft\\Windows\\Application Experience\\AitAgent" },
        { "type": "task", "name": "\\Microsoft\\Windows\\Customer Experience Improvement Program\\Consolidator" },
        { "type": "task", "name": "\\Microsoft\\Windows\\Customer Experience Improvement Program\\UsbCeip" },
        { "type": "task", "name": "\\Microsoft\\Windows\\DiskDiagnostic\\Microsoft-Windows-DiskDiagnosticDataCollector" }
      ]
    }
  ],
  "advanced": [
    { "type": "service", "name": "RetailDemo", "description": "Mode demo magasin" },
    { "type": "service", "name": "MapsBroker", "description": "Cartes hors ligne" },
    { "type": "service", "name": "WMPNetworkSvc", "description": "Partage Windows Media Player" },
    { "type": "service", "name": "PhoneSvc", "description": "Telephonie VoIP Windows" },
    { "type": "service", "name": "SCardSvr", "description": "Carte a puce" },
    { "type": "service", "name": "ScDeviceEnum", "description": "Enumeration cartes a puce" },
    { "type": "service", "name": "SEMgrSvc", "description": "Paiement NFC / elements securises" },
    { "type": "service", "name": "SharedAccess", "description": "Partage de connexion Internet" },
    { "type": "service", "name": "WalletService", "description": "Portefeuille Windows" },
    { "type": "appx", "name": "Microsoft.BingNews", "description": "App Actualites" },
    { "type": "appx", "name": "Microsoft.BingWeather", "description": "App Meteo" },
    { "type": "appx", "name": "Microsoft.YourPhone", "description": "Mobile connecte" },
    { "type": "appx", "name": "Microsoft.MicrosoftSolitaireCollection", "description": "Solitaire" },
    { "type": "appx", "name": "Microsoft.People", "description": "App Contacts" },
    { "type": "appx", "name": "MicrosoftTeams", "description": "Teams personnel preinstalle" },
    { "type": "appx", "name": "Clipchamp.Clipchamp", "description": "Editeur video" },
    { "type": "appx", "name": "Microsoft.ZuneMusic", "description": "Groove Music" },
    { "type": "appx", "name": "Microsoft.ZuneVideo", "description": "Films & TV" },
    { "type": "feature", "name": "Internet-Explorer-Optional-amd64", "description": "Internet Explorer 11" },
    { "type": "feature", "name": "WindowsMediaPlayer", "description": "Windows Media Player classique" },
    { "type": "feature", "name": "WorkFolders-Client", "description": "Dossiers de travail entreprise" }
  ]
}
```

- [ ] **Step 2: Validate the new catalog by running the full test suite**

Run: `pwsh -c "Invoke-Pester -Path tests/"`
Expected: All tests PASS (including `Read-Catalog` loading this file).

- [ ] **Step 3: Commit**

```bash
git add catalog.json
git commit -m "feat: catalogue complet (14 categories + 21 items avances)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 17: README finalisation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite `README.md` with complete usage + safety notes**

```markdown
# Windows Services Optimizer

Script PowerShell interactif pour alleger Windows 11 (build >= 22621) en posant des questions d'usage puis en desactivant les services, taches planifiees, fonctionnalites optionnelles et paquets AppX non utilises.

## Prerequis

- Windows 11 22H2 ou superieur (build >= 22621)
- PowerShell 5.1+ (inclus dans Windows 11)
- Droits administrateur

## Utilisation

### Mode simulation (recommande pour decouvrir)

```powershell
.\Optimize-Windows.ps1 -DryRun
```

Aucune modification n'est appliquee. Les questions sont posees et le script affiche ce qui serait fait.

### Mode reel

```powershell
.\Optimize-Windows.ps1
```

Le script :
1. Verifie l'elevation administrateur et la version Windows.
2. Cree un point de restauration systeme.
3. Exporte l'etat actuel de tous les items concernes dans `backups/<timestamp>/`.
4. Te pose une quinzaine de questions par categorie d'usage (imprimante, Xbox, Bluetooth, etc.).
5. Te propose une section avancee item par item.
6. Affiche un recapitulatif et demande confirmation finale.
7. Applique les modifications et genere `Restore-<timestamp>.ps1` pour annuler.

## Restauration

Trois niveaux :

1. **Restauration fine** : executer `backups/<timestamp>/Restore-<timestamp>.ps1` en admin pour reactiver uniquement les elements modifies.
2. **Restauration systeme** : utiliser le point de restauration cree automatiquement.
3. **Paquets AppX** : doivent etre reinstalles manuellement via le Microsoft Store (limitation technique).

## Services protegees

Le script refuse categoriquement de desactiver les services vitaux (Audio, WinDefend, RpcSs, etc.) meme s'ils figurent dans le catalogue. La liste exacte est definie dans `$script:ProtectedServices` dans le script.

## Catalogue

Le fichier `catalog.json` contient 14 categories et 21 items avances. Tu peux l'editer pour personnaliser les questions ou ajouter des services — le script valide la structure au demarrage.

## Tests

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
Invoke-Pester -Path tests/
```

## Avertissements

- Teste d'abord en `-DryRun`.
- Desactiver la telemetrie et certains services Xbox/OneDrive peut affecter des fonctionnalites Windows (Store, Hello, etc.).
- Sur une machine professionnelle, verifie avec ton admin IT avant de desinstaller Teams ou des features Entreprise.

## Design

Voir `docs/superpowers/specs/2026-04-21-windows-services-optimizer-design.md`.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: README complet (usage, restauration, avertissements)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 18: Final test pass + manual DryRun verification

**Files:**
- None (verification only)

- [ ] **Step 1: Run the full Pester suite**

Run: `pwsh -c "Invoke-Pester -Path tests/ -Output Detailed"`
Expected: **All tests PASS**. If any failure, stop here and fix — do not claim completion.

- [ ] **Step 2: Syntactic parse check**

Run: `pwsh -c "[System.Management.Automation.Language.Parser]::ParseFile('./Optimize-Windows.ps1', [ref]\$null, [ref]\$null) | Out-Null ; Write-Host 'OK'"`
Expected: `OK` (no syntax errors).

- [ ] **Step 3: (If a Windows 11 VM is available) Manual DryRun**

On a Windows 11 VM with admin elevation :
```powershell
.\Optimize-Windows.ps1 -DryRun
```
Answer a few categories, reach the summary screen, confirm the flow completes and a `backups/<timestamp>/` directory contains the 4 CSVs + an empty-body `Restore-*.ps1`.

If no VM is available, document this explicitly in the final report — do NOT claim Windows-side validation.

- [ ] **Step 4: Tag the release**

```bash
git tag -a v0.1.0 -m "Initial release"
```

---

## Self-Review

**Spec coverage check** (walked each section of the design doc) :

| Spec section | Task(s) |
|--------------|---------|
| §3 Architecture — file structure | Task 1 |
| §3 — engine responsibilities | Tasks 2, 3, 15 |
| §3 — handlers (4 types) | Tasks 7, 8, 9, 10 + dispatch Task 11 |
| §4 Catalog format + validation | Task 2 |
| §5 Execution flow — elevation + version check | Task 3 + 15 |
| §5 — backup directory + CSV exports | Task 5 |
| §5 — restore point | Task 6 |
| §5 — category phase | Task 12 |
| §5 — advanced phase | Task 12 |
| §5 — summary + final confirmation | Task 14 |
| §5 — apply + log + restore append | Task 15 |
| §5 — final report | Task 15 |
| §6 Restore script header | Task 13 |
| §6 — restore commands per type | Tasks 7, 8, 9, 10 |
| §6 — AppX limitation documented | Task 10 + README Task 17 |
| §7 Catalog content (14 + 21) | Task 16 |
| §7 Protected services blacklist | Task 1 (constants) + Task 7 (guard) |
| §8 Error handling (try/catch per handler) | Tasks 7–10 |
| §9 Tests (Pester + DryRun mode) | All tasks (TDD) + Task 18 manual |

No uncovered section.

**Placeholder scan** : no TBD/TODO/"implement later"/unspecified types. Every step contains the exact code or command.

**Type consistency check** :
- Decision objects are always raw catalog items (`type`, `name`, optional `description`) — consistent from Task 12 producers to Task 15 consumer via Task 11 dispatcher.
- Handler return shape `[pscustomobject]@{ Success; Reason }` consistent across Tasks 7, 8, 9, 10 and checked in Task 11 and Task 15.
- `RestoreScriptPath` parameter name identical across all handlers.
- Function names match their test references (e.g., `Disable-ServiceItem`, `Get-SummaryCounts`).
