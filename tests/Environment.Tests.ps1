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
        $result = Get-CurrentWindowsBuild
        $result | Should -BeOfType [int]
    }
}
