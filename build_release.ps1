param(
    [switch]$AndroidOnly,
    [switch]$WindowsOnly,
    [switch]$SkipAnalyze,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Invoke-Step {
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
    } else {
        $parent = [System.IO.Path]::GetDirectoryName($CandidatePath)
        if ($parent -and (Test-Path -LiteralPath $parent)) {
            $resolvedParent = (Resolve-Path -LiteralPath $parent).Path
            if (-not $resolvedParent.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to create artifact outside repo root: $resolvedParent"
            }
        }
    }
}

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -LiteralPath $repoRoot

if ($AndroidOnly -and $WindowsOnly) {
    throw "Use only one of -AndroidOnly or -WindowsOnly."
}

$buildAndroid = -not $WindowsOnly
$buildWindows = -not $AndroidOnly

$androidArtifact = Join-Path $repoRoot 'AniVault-android-release.apk'
$windowsArtifactDir = Join-Path $repoRoot 'AniVault-windows-release'

Assert-WithinRoot -CandidatePath $androidArtifact -RootPath $repoRoot
Assert-WithinRoot -CandidatePath $windowsArtifactDir -RootPath $repoRoot

Invoke-Step -Message 'Fetch Flutter dependencies' -Action { flutter pub get }

if (-not $SkipAnalyze) {
    Invoke-Step -Message 'Run flutter analyze' -Action { flutter analyze }
}

if (-not $SkipTests) {
    Invoke-Step -Message 'Run flutter test' -Action { flutter test }
}

if ($buildAndroid) {
    Invoke-Step -Message 'Build Android release APK' -Action { flutter build apk --release }

    $sourceApk = Join-Path $repoRoot 'build\app\outputs\flutter-apk\app-release.apk'
    if (-not (Test-Path -LiteralPath $sourceApk)) {
        throw "Android build finished but APK was not found at $sourceApk"
    }

    if (Test-Path -LiteralPath $androidArtifact) {
        Remove-Item -LiteralPath $androidArtifact -Force
    }

    Copy-Item -LiteralPath $sourceApk -Destination $androidArtifact -Force
    Write-Host "Android artifact: $androidArtifact" -ForegroundColor Green
}

if ($buildWindows) {
    Invoke-Step -Message 'Build Windows release bundle' -Action { flutter build windows --release }

    $sourceDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
    if (-not (Test-Path -LiteralPath $sourceDir)) {
        throw "Windows build finished but release directory was not found at $sourceDir"
    }

    if (Test-Path -LiteralPath $windowsArtifactDir) {
        Remove-Item -LiteralPath $windowsArtifactDir -Recurse -Force
    }

    New-Item -ItemType Directory -Path $windowsArtifactDir | Out-Null
    Get-ChildItem -LiteralPath $sourceDir -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $windowsArtifactDir -Recurse -Force
    }

    Write-Host "Windows artifact: $windowsArtifactDir" -ForegroundColor Green
}

Write-Host ""
Write-Host "Build complete." -ForegroundColor Green
