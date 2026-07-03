#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

export GOWORK=off
export CGO_ENABLED=1
export GOOS=ios
export GOARCH=arm64

SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
export CC="$(xcrun --sdk iphoneos --find clang)"
export CGO_CFLAGS="-isysroot ${SDK_PATH} -miphoneos-version-min=13.0"
export CGO_LDFLAGS="-isysroot ${SDK_PATH} -miphoneos-version-min=13.0"

OUT_DIR="../../ios/Runner"
mkdir -p "${OUT_DIR}"
go build -buildmode=c-archive -o "${OUT_DIR}/libanivault_torrent.a" .
