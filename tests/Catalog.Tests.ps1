BeforeAll {
    . "$PSScriptRoot/../Optimize-Windows.ps1"
}

Describe 'Catalog validation' {
    It 'placeholder' {
        $true | Should -Be $true
    }
}
