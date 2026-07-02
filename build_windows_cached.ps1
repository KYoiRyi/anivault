param(
    [switch]$ForceBuild,
    [switch]$Clean,
    [switch]$SkipPubGet,
    [string[]]$FlutterArgs = @()
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Invoke-Checked {
    param(
        [string]$Message,
        [scriptblock]$Action
    )

    Write-Step $Message
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$Message failed with exit code $LASTEXITCODE."
    }
}

function Assert-NotLockedByRunningProcess {
    param([string]$ExecutablePath)

    if (-not (Test-Path -LiteralPath $ExecutablePath)) {
        return
    }

    $resolvedExecutable = (Resolve-Path -LiteralPath $ExecutablePath).Path
    $processes = Get-CimInstance Win32_Process |
        Where-Object { $_.ExecutablePath -and ($_.ExecutablePath -eq $resolvedExecutable) }

    if ($processes) {
        $processList = ($processes | ForEach-Object { "$($_.Name) PID $($_.ProcessId)" }) -join ', '
        throw "Release executable is running and blocks linking: $resolvedExecutable ($processList). Close it or stop the process, then run this script again."
    }
}

function Assert-WithinRoot {
    param(
        [string]$CandidatePath,
        [string]$RootPath
    )

    $resolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path
    if (Test-Path -LiteralPath $CandidatePath) {
        $resolvedCandidate = (Resolve-Path -LiteralPath $CandidatePath).Path
        if (-not $resolvedCandidate.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to touch path outside repo root: $resolvedCandidate"
        }
        return
    }

    $parent = [System.IO.Path]::GetDirectoryName($CandidatePath)
    if ($parent -and (Test-Path -LiteralPath $parent)) {
        $resolvedParent = (Resolve-Path -LiteralPath $parent).Path
        if (-not $resolvedParent.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to create path outside repo root: $resolvedParent"
        }
    }
}

function Get-InputFingerprint {
    param([string]$RootPath)

    $roots = @(
        'pubspec.yaml',
        'pubspec.lock',
        'analysis_options.yaml',
        'lib',
        'assets',
        'windows',
        'native',
        'third_party'
    )

    $files = foreach ($item in $roots) {
        $path = Join-Path $RootPath $item
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        if ((Get-Item -LiteralPath $path).PSIsContainer) {
            Get-ChildItem -LiteralPath $path -Recurse -File -Force |
                Where-Object {
                    $_.FullName -notmatch '\\(build|target|\.dart_tool)\\' -and
                    $_.Extension -notin @('.dll', '.lib', '.a', '.exe', '.pdb', '.ilk', '.obj', '.log')
                }
        } else {
            Get-Item -LiteralPath $path
        }
    }

    $rootUri = New-Object System.Uri (($RootPath.TrimEnd('\') + '\'))
    $hashInput = foreach ($file in ($files | Sort-Object FullName)) {
        $fileUri = New-Object System.Uri $file.FullName
        $relativePath = [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($fileUri).ToString()).Replace('/', '\')
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
        "$relativePath`t$hash"
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes(($hashInput -join "`n"))
        [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $repoRoot

$cacheRoot = Join-Path $repoRoot '.build-cache'
$pubCache = Join-Path $cacheRoot 'pub-cache'
$stampFile = Join-Path $cacheRoot 'windows-release.sha256'
$buildDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$artifactDir = Join-Path $repoRoot 'AniVault-windows-release'

Assert-WithinRoot -CandidatePath $cacheRoot -RootPath $repoRoot
Assert-WithinRoot -CandidatePath $artifactDir -RootPath $repoRoot

New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null
New-Item -ItemType Directory -Path $pubCache -Force | Out-Null

$env:PUB_CACHE = $pubCache
if (-not $env:CMAKE_BUILD_PARALLEL_LEVEL) {
    $env:CMAKE_BUILD_PARALLEL_LEVEL = [string][Math]::Max(1, [Environment]::ProcessorCount)
}

if ($Clean) {
    Write-Step 'Clean Windows build cache'
    $windowsBuildRoot = Join-Path $repoRoot 'build\windows'
    Assert-WithinRoot -CandidatePath $windowsBuildRoot -RootPath $repoRoot
    if (Test-Path -LiteralPath $windowsBuildRoot) {
        Remove-Item -LiteralPath $windowsBuildRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $stampFile) {
        Remove-Item -LiteralPath $stampFile -Force
    }
}

if (-not $SkipPubGet) {
    Invoke-Checked -Message 'Fetch Flutter dependencies with local Pub cache' -Action {
        flutter pub get
    }
}

$fingerprint = Get-InputFingerprint -RootPath $repoRoot
$previousFingerprint = if (Test-Path -LiteralPath $stampFile) {
    (Get-Content -LiteralPath $stampFile -Raw).Trim()
} else {
    ''
}

Assert-NotLockedByRunningProcess -ExecutablePath (Join-Path $artifactDir 'anivault.exe')

$hasReleaseOutput = Test-Path -LiteralPath (Join-Path $buildDir 'anivault.exe')
if (-not $ForceBuild -and $hasReleaseOutput -and $fingerprint -eq $previousFingerprint) {
    Write-Step 'Inputs unchanged; reuse cached Windows release build'
} else {
    Assert-NotLockedByRunningProcess -ExecutablePath (Join-Path $buildDir 'anivault.exe')
    Invoke-Checked -Message 'Build Windows release bundle incrementally' -Action {
        flutter build windows --release @FlutterArgs
    }
    Set-Content -LiteralPath $stampFile -Value $fingerprint -Encoding ASCII
}

if (-not (Test-Path -LiteralPath $buildDir)) {
    throw "Windows build finished but release directory was not found at $buildDir"
}

Write-Step 'Copy Windows release artifact'
if (Test-Path -LiteralPath $artifactDir) {
    Remove-Item -LiteralPath $artifactDir -Recurse -Force
}

New-Item -ItemType Directory -Path $artifactDir | Out-Null
Get-ChildItem -LiteralPath $buildDir -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $artifactDir -Recurse -Force
}

Write-Host ""
Write-Host "Windows artifact: $artifactDir" -ForegroundColor Green
Write-Host "Build cache: $cacheRoot" -ForegroundColor Green
Write-Host "Done." -ForegroundColor Green
