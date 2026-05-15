param(
    [switch]$NoCommit,
    [switch]$NoPush
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$SkillsRoot = Join-Path $RepoRoot "skills"
$GitSafeDir = $RepoRoot.Replace("\", "/")

$Sources = @(
    [pscustomobject]@{
        Name = "codex"
        Root = "C:\Users\User\.codex\skills"
        RepoSubdir = "codex"
        Label = "Codex local skills"
    },
    [pscustomobject]@{
        Name = "agents"
        Root = "C:\Users\User\.agents\skills"
        RepoSubdir = "agents"
        Label = "Agents local skills"
    }
)

$ExcludedDirectoryNames = @(
    ".git",
    ".codex",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
    "__pycache__",
    "node_modules"
)

$ExcludedFileNames = @(
    ".DS_Store",
    "Thumbs.db"
)

$ExcludedFileExtensions = @(
    ".pyc",
    ".pyo"
)

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Test-ExcludedDirectory {
    param([System.IO.DirectoryInfo]$Directory)

    return $ExcludedDirectoryNames -contains $Directory.Name
}

function Test-ExcludedFile {
    param([System.IO.FileInfo]$File)

    if ($ExcludedFileNames -contains $File.Name) {
        return $true
    }

    return $ExcludedFileExtensions -contains $File.Extension.ToLowerInvariant()
}

function Get-ResolvedDirectoryPath {
    param([System.IO.DirectoryInfo]$Directory)

    if ($Directory.LinkType -and $Directory.Target) {
        $target = @($Directory.Target)[0]
        if ($target) {
            return [string]$target
        }
    }

    return $Directory.FullName
}

function Copy-DirectoryContents {
    param(
        [string]$Source,
        [string]$Destination,
        [hashtable]$Visited
    )

    $resolved = (Resolve-Path -LiteralPath $Source).ProviderPath
    $visitedKey = $resolved.ToLowerInvariant()

    if ($Visited.ContainsKey($visitedKey)) {
        Write-Warning "Skipped recursive link: $Source"
        return
    }

    $Visited[$visitedKey] = $true
    Ensure-Directory $Destination

    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        if ($item.PSIsContainer) {
            if (Test-ExcludedDirectory $item) {
                continue
            }

            $childSource = Get-ResolvedDirectoryPath $item
            $childDestination = Join-Path $Destination $item.Name
            Copy-DirectoryContents -Source $childSource -Destination $childDestination -Visited $Visited
            continue
        }

        if (Test-ExcludedFile $item) {
            continue
        }

        $targetPath = Join-Path $Destination $item.Name
        Copy-Item -LiteralPath $item.FullName -Destination $targetPath -Force
    }

    $Visited.Remove($visitedKey)
}

function Get-RelativePath {
    param(
        [string]$BasePath,
        [string]$FullPath
    )

    $base = (Resolve-Path -LiteralPath $BasePath).ProviderPath.TrimEnd("\") + "\"
    $full = (Resolve-Path -LiteralPath $FullPath).ProviderPath

    if ($full.Length -lt $base.Length) {
        return ""
    }

    return $full.Substring($base.Length)
}

function Normalize-FrontMatterValue {
    param([string]$Value)

    if (-not $Value) {
        return ""
    }

    $normalized = $Value.Trim()
    $normalized = $normalized.Trim('"')
    $normalized = $normalized.Trim("'")
    $normalized = ($normalized -replace "\s+", " ").Trim()
    return $normalized
}

function Get-FrontMatterValue {
    param(
        [string]$Path,
        [string]$Key
    )

    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    if ($lines.Count -lt 3 -or $lines[0] -ne "---") {
        return ""
    }

    $pattern = "^\s*" + [regex]::Escape($Key) + "\s*:\s*(.*)$"
    $index = 1

    while ($index -lt $lines.Count -and $lines[$index] -ne "---") {
        $line = $lines[$index]

        if ($line -match $pattern) {
            $rawValue = $Matches[1].Trim()

            if ($rawValue -match "^[>|]") {
                $parts = @()
                $cursor = $index + 1

                while ($cursor -lt $lines.Count -and $lines[$cursor] -ne "---") {
                    if ($lines[$cursor] -match "^[A-Za-z0-9_-]+\s*:") {
                        break
                    }

                    $parts += $lines[$cursor].Trim()
                    $cursor += 1
                }

                return Normalize-FrontMatterValue ($parts -join " ")
            }

            return Normalize-FrontMatterValue $rawValue
        }

        $index += 1
    }

    return ""
}

function Escape-MarkdownCell {
    param([string]$Value)

    if (-not $Value) {
        return ""
    }

    return (($Value -replace "\|", "\|") -replace "`r?`n", " ").Trim()
}

function Get-SkillRecords {
    $records = @()

    foreach ($source in $Sources) {
        $destinationRoot = Join-Path $SkillsRoot $source.RepoSubdir

        if (-not (Test-Path -LiteralPath $destinationRoot)) {
            continue
        }

        $skillFiles = Get-ChildItem -LiteralPath $destinationRoot -Filter "SKILL.md" -Recurse -Force -File |
            Where-Object {
                $relativeFile = Get-RelativePath -BasePath $destinationRoot -FullPath $_.FullName
                $isExcluded = $false

                foreach ($excluded in $ExcludedDirectoryNames) {
                    if ($relativeFile -like "*\$excluded\*") {
                        $isExcluded = $true
                        break
                    }
                }

                -not $isExcluded
            }

        foreach ($skillFile in $skillFiles) {
            $skillDirectory = Split-Path -Parent $skillFile.FullName
            $relativeSkillDirectory = Get-RelativePath -BasePath $destinationRoot -FullPath $skillDirectory
            $repoDirectory = ("skills/" + $source.RepoSubdir + "/" + $relativeSkillDirectory).Replace("\", "/").TrimEnd("/")
            $sourceDirectory = Join-Path $source.Root $relativeSkillDirectory
            $name = Get-FrontMatterValue -Path $skillFile.FullName -Key "name"
            $description = Get-FrontMatterValue -Path $skillFile.FullName -Key "description"

            if (-not $name) {
                $name = Split-Path -Leaf $skillDirectory
            }

            $records += [pscustomobject]@{
                Name = $name
                Source = $source.Name
                RepoDirectory = $repoDirectory
                LocalDirectory = $sourceDirectory
                Description = $description
            }
        }
    }

    return $records | Sort-Object Source, RepoDirectory
}

function Write-Readme {
    param([array]$SkillRecords)

    $lines = @()
    $lines += '# codexSkill'
    $lines += ''
    $lines += 'This repository synchronizes the locally installed Codex/Agents skills on this machine and generates an index.'
    $lines += ''
    $lines += '## Usage'
    $lines += ''
    $lines += '1. In Codex, mention a skill name such as `$nature-polishing`, or ask for a task matching that skill description.'
    $lines += '2. Each skill directory is listed below. The entry point is normally `SKILL.md`.'
    $lines += '3. `skills/codex` is copied from `C:\Users\User\.codex\skills`; `skills/agents` is copied from `C:\Users\User\.agents\skills`.'
    $lines += '4. The sync script only adds or overwrites files. It does not automatically delete stale files that disappeared from the source directories.'
    $lines += ''
    $lines += '## Manual Sync'
    $lines += ''
    $lines += '```powershell'
    $lines += 'powershell -NoProfile -ExecutionPolicy Bypass -File scripts/sync-skills.ps1'
    $lines += '```'
    $lines += ''
    $lines += 'Generate files without committing or pushing:'
    $lines += ''
    $lines += '```powershell'
    $lines += 'powershell -NoProfile -ExecutionPolicy Bypass -File scripts/sync-skills.ps1 -NoCommit -NoPush'
    $lines += '```'
    $lines += ''
    $lines += '## Skill Directory Index'
    $lines += ''
    $lines += '| Skill | Source | Repository directory | Local directory | Usage notes |'
    $lines += '| --- | --- | --- | --- | --- |'

    foreach ($record in $SkillRecords) {
        $name = Escape-MarkdownCell $record.Name
        $source = Escape-MarkdownCell $record.Source
        $repoDir = Escape-MarkdownCell $record.RepoDirectory
        $localDir = Escape-MarkdownCell $record.LocalDirectory
        $description = Escape-MarkdownCell $record.Description

        $lines += ('| `{0}` | `{1}` | `{2}` | `{3}` | {4} |' -f $name, $source, $repoDir, $localDir, $description)
    }

    Set-Content -LiteralPath (Join-Path $RepoRoot "README.md") -Value $lines -Encoding UTF8
}

function Invoke-Git {
    param([string[]]$Arguments)

    & git -c "safe.directory=$GitSafeDir" @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

Ensure-Directory $SkillsRoot

foreach ($source in $Sources) {
    if (-not (Test-Path -LiteralPath $source.Root)) {
        Write-Warning "Source does not exist: $($source.Root)"
        continue
    }

    $destinationRoot = Join-Path $SkillsRoot $source.RepoSubdir
    Write-Host "Syncing $($source.Root) -> $destinationRoot"
    Copy-DirectoryContents -Source $source.Root -Destination $destinationRoot -Visited @{}
}

$skillRecords = Get-SkillRecords
Write-Readme -SkillRecords $skillRecords

Write-Host "Indexed $($skillRecords.Count) skills."

if ($NoCommit) {
    Write-Host "NoCommit was set. Skipping git commit and push."
    exit 0
}

Invoke-Git @("add", "README.md", ".gitignore", "scripts/sync-skills.ps1", "skills")

$status = & git -c "safe.directory=$GitSafeDir" status --porcelain
if (-not $status) {
    Write-Host "No changes to commit."
    if (-not $NoPush) {
        Invoke-Git @("push")
    }
    exit 0
}

$date = Get-Date -Format "yyyy-MM-dd"
Invoke-Git @("commit", "-m", "sync installed skills: $date")

if ($NoPush) {
    Write-Host "NoPush was set. Skipping git push."
    exit 0
}

Invoke-Git @("push")
