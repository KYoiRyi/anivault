#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

NDK_ROOT="${ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME:-${ANDROID_NDK_LATEST_HOME:-}}}"
API_LEVEL="${ANDROID_API_LEVEL:-24}"
if [[ -z "${NDK_ROOT}" || ! -d "${NDK_ROOT}" ]]; then
  echo "Android NDK not found. Set ANDROID_NDK_ROOT or ANDROID_NDK_HOME." >&2
  exit 1
fi

case "$(uname -s)" in
  Darwin) HOST_TAG="darwin-x86_64" ;;
  Linux) HOST_TAG="linux-x86_64" ;;
  *) echo "Unsupported host OS: $(uname -s)" >&2; exit 1 ;;
esac

TOOLCHAIN_BIN="${NDK_ROOT}/toolchains/llvm/prebuilt/${HOST_TAG}/bin"
OUT_ROOT="../../android/app/src/main/jniLibs"

export GOWORK=off
export CGO_ENABLED=1
export GOOS=android

build_target() {
  local abi="$1"
  local goarch="$2"
  local cc="$3"
  local goarm="${4:-}"

  export GOARCH="${goarch}"
  export CC="${TOOLCHAIN_BIN}/${cc}"
  if [[ -n "${goarm}" ]]; then
    export GOARM="${goarm}"
  else
    unset GOARM || true
  fi

  mkdir -p "${OUT_ROOT}/${abi}"
  go build -buildmode=c-shared -o "${OUT_ROOT}/${abi}/libanivault_torrent.so" .
}

build_target "arm64-v8a" "arm64" "aarch64-linux-android${API_LEVEL}-clang"
build_target "armeabi-v7a" "arm" "armv7a-linux-androideabi${API_LEVEL}-clang" "7"
build_target "x86_64" "amd64" "x86_64-linux-android${API_LEVEL}-clang"
