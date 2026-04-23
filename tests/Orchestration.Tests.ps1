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

Describe 'Invoke-Optimization end-to-end (DryRun)' {
    It 'runs through the flow without modifications when DryRun is set' {
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
        Mock -CommandName Read-YesNoSkip -MockWith { 'yes' }
        Mock -CommandName Get-Service -MockWith {
            [pscustomobject]@{ Name='Spooler'; DisplayName='Print Spooler'; Status='Running'; StartType='Automatic' }
        }
        Mock -CommandName Enable-ComputerRestore -MockWith { }
        Mock -CommandName Checkpoint-Computer -MockWith { }

        try {
            $result = Invoke-Optimization -CatalogPath $catalogPath -BackupRoot $backupRoot -DryRun
            $result.ExitCode | Should -Be 0
            Test-Path $backupRoot | Should -BeTrue
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

Describe 'Select-ExistingItems' {
    It 'keeps only items that exist on the machine and drops empty categories' {
        Mock -CommandName Test-ItemExists -MockWith {
            param($Item) return ($Item.name -in @('Spooler','Fax','Keep'))
        }
        $catalog = [pscustomobject]@{
            version = '1.1'
            minWindowsBuild = 22621
            categories = @(
                [pscustomobject]@{ id='printing'; question='?'; keepIfYes=$true; items=@(
                    [pscustomobject]@{ type='service'; name='Spooler' },
                    [pscustomobject]@{ type='service'; name='Ghost'   }   # absent
                )},
                [pscustomobject]@{ id='oem_dell'; question='?'; keepIfYes=$true; items=@(
                    [pscustomobject]@{ type='service'; name='DellTechHub' },   # absent
                    [pscustomobject]@{ type='service'; name='DellPairService' } # absent
                )}
            )
            advanced = @(
                [pscustomobject]@{ type='service'; name='Keep' },
                [pscustomobject]@{ type='service'; name='Gone' }
            )
        }
        $r = Select-ExistingItems -Catalog $catalog
        $r.Catalog.categories.Count | Should -Be 1
        $r.Catalog.categories[0].id | Should -Be 'printing'
        $r.Catalog.categories[0].items.Count | Should -Be 1
        $r.Catalog.advanced.Count | Should -Be 1
        # 1 (Ghost) + 2 (Dell) + 1 (Gone advanced) = 4 items absents
        $r.SkippedItems      | Should -Be 4
        $r.SkippedCategories | Should -Be 1
    }

    It 'returns catalog unchanged when every item exists' {
        Mock -CommandName Test-ItemExists -MockWith { $true }
        $catalog = [pscustomobject]@{
            version = '1.1'
            categories = @(
                [pscustomobject]@{ id='x'; question='?'; keepIfYes=$true; items=@(
                    [pscustomobject]@{ type='service'; name='A' }
                )}
            )
            advanced = @()
        }
        $r = Select-ExistingItems -Catalog $catalog
        $r.SkippedItems      | Should -Be 0
        $r.SkippedCategories | Should -Be 0
        $r.Catalog.categories.Count | Should -Be 1
    }
}

Describe 'Test-ItemExists' {
    It 'returns $true without probing on non-Windows platforms' {
        Mock -CommandName Test-IsWindowsPlatform -MockWith { $false }
        Mock -CommandName Get-Service -MockWith { throw 'should not be called' }
        Test-ItemExists -Item ([pscustomobject]@{ type='service'; name='Whatever' }) | Should -BeTrue
        Should -Invoke Get-Service -Times 0
    }

    It 'returns $true when Get-Service finds the service' {
        Mock -CommandName Test-IsWindowsPlatform -MockWith { $true }
        Mock -CommandName Get-Service -MockWith { [pscustomobject]@{ Name='Spooler' } }
        Test-ItemExists -Item ([pscustomobject]@{ type='service'; name='Spooler' }) | Should -BeTrue
    }

    It 'returns $false when Get-Service returns nothing' {
        Mock -CommandName Test-IsWindowsPlatform -MockWith { $true }
        Mock -CommandName Get-Service -MockWith { $null }
        Test-ItemExists -Item ([pscustomobject]@{ type='service'; name='Ghost' }) | Should -BeFalse
    }

    It 'returns $false when AppX package is not installed' {
        Mock -CommandName Test-IsWindowsPlatform -MockWith { $true }
        Mock -CommandName Get-AppxPackage -MockWith { $null }
        Test-ItemExists -Item ([pscustomobject]@{ type='appx'; name='Nope' }) | Should -BeFalse
    }

    It 'returns $false when optional feature is absent' {
        Mock -CommandName Test-IsWindowsPlatform -MockWith { $true }
        Mock -CommandName Get-WindowsOptionalFeature -MockWith { $null }
        Test-ItemExists -Item ([pscustomobject]@{ type='feature'; name='Missing' }) | Should -BeFalse
    }
}
