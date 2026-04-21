BeforeAll {
    . "$PSScriptRoot/_Stubs.ps1"
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
