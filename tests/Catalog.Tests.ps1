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
        $cat.version | Should -Match '^\d+\.\d+$'
    }

    It 'throws on missing file' {
        { Read-Catalog -Path '/nonexistent/path.json' } | Should -Throw
    }
}
