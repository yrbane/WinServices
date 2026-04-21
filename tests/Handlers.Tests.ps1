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
