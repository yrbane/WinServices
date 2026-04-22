BeforeAll {
    . "$PSScriptRoot/_Stubs.ps1"
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
            (Get-Content $tmp -Raw) | Should -Match 'Enable-ScheduledTask -TaskPath ''\\Microsoft\\Windows\\App\\'' -TaskName ''Foo'''
        } finally {
            Remove-Item $tmp -Force
        }
    }

    It 'returns success (absent) when task not found' {
        Mock -CommandName Get-ScheduledTask -MockWith { throw 'not found' }
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            $r = Disable-TaskItem -FullPath '\Missing\Task' -RestoreScriptPath $tmp -DryRun:$false
            $r.Success | Should -BeTrue
            $r.Reason  | Should -Match 'absente'
        } finally {
            Remove-Item $tmp -Force
        }
    }
}

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
