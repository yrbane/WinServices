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
