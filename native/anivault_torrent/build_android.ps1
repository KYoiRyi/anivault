param(
    [Parameter(Mandatory = $true)]
    [string]$NdkRoot,
    [string]$ApiLevel = '24'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $root '..\..')
$outRoot = Join-Path $repoRoot 'android\app\src\main\jniLibs'
$env:GOWORK = 'off'
$env:CGO_ENABLED = '1'
$env:GOOS = 'android'

$targets = @(
    @{ Abi = 'arm64-v8a'; GoArch = 'arm64'; Tool = "aarch64-linux-android$ApiLevel-clang.cmd"; Triple = 'aarch64-linux-android' },
    @{ Abi = 'armeabi-v7a'; GoArch = 'arm'; GoArm = '7'; Tool = "armv7a-linux-androideabi$ApiLevel-clang.cmd"; Triple = 'arm-linux-androideabi' },
    @{ Abi = 'x86_64'; GoArch = 'amd64'; Tool = "x86_64-linux-android$ApiLevel-clang.cmd"; Triple = 'x86_64-linux-android' }
)

$hostTag = 'windows-x86_64'
$toolchainBin = Join-Path $NdkRoot "toolchains\llvm\prebuilt\$hostTag\bin"
if (-not (Test-Path -LiteralPath $toolchainBin)) {
    throw "NDK LLVM toolchain not found: $toolchainBin"
}

function Find-CxxShared {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Abi,
        [Parameter(Mandatory = $true)]
        [string]$Triple,
        [Parameter(Mandatory = $true)]
        [string]$Cxx
    )

    $candidates = @(
        (Join-Path $NdkRoot "sources\cxx-stl\llvm-libc++\libs\$Abi\libc++_shared.so"),
        (Join-Path $NdkRoot "toolchains\llvm\prebuilt\$hostTag\sysroot\usr\lib\$Abi\libc++_shared.so"),
        (Join-Path $NdkRoot "toolchains\llvm\prebuilt\$hostTag\sysroot\usr\lib\$Triple\libc++_shared.so")
    )
    if (Test-Path -LiteralPath $Cxx) {
        $printed = & $Cxx '-print-file-name=libc++_shared.so'
        if ($printed) {
            $candidates += $printed.Trim()
        }
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    $match = Get-ChildItem -LiteralPath $NdkRoot -Recurse -Filter 'libc++_shared.so' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like "*$Abi*" -or $_.FullName -like "*$Triple*" } |
        Select-Object -First 1
    if ($match) {
        return $match.FullName
    }

    return $null
}

Push-Location -LiteralPath $root
try {
    foreach ($target in $targets) {
        $env:GOARCH = $target.GoArch
        if ($target.GoArm) {
            $env:GOARM = $target.GoArm
        } else {
            Remove-Item Env:\GOARM -ErrorAction SilentlyContinue
        }
        $env:CC = Join-Path $toolchainBin $target.Tool
        $cxx = $env:CC -replace 'clang\.cmd$', 'clang++.cmd'
        $outDir = Join-Path $outRoot $target.Abi
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        go build -buildmode=c-shared -o (Join-Path $outDir 'libanivault_torrent.so') .
        if ($LASTEXITCODE -ne 0) {
            throw "Android torrent native build failed for $($target.Abi)"
        }
        $cxxShared = Find-CxxShared -Abi $target.Abi -Triple $target.Triple -Cxx $cxx
        if (-not (Test-Path -LiteralPath $cxxShared)) {
            throw "Missing libc++_shared.so for $($target.Abi) under $NdkRoot"
        }
        Copy-Item -LiteralPath $cxxShared -Destination (Join-Path $outDir 'libc++_shared.so') -Force
    }
} finally {
    Pop-Location
}
