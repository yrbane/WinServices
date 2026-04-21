BeforeAll {
    . "$PSScriptRoot/_Stubs.ps1"
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

Describe 'Get-SummaryCounts' {
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
