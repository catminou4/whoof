#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CORE_DIR="$(cd "$APP_DIR/../goose/core" && pwd)"
RUST_DIR="$APP_DIR/Rust"

CONFIGURATION="${CONFIGURATION:-Debug}"
PLATFORM_NAME="${PLATFORM_NAME:-iphonesimulator}"
CURRENT_ARCH="${CURRENT_ARCH:-${ARCHS:-arm64}}"

case "$CONFIGURATION" in
  Release|Profile)
    CARGO_RELEASE=1
    CARGO_PROFILE_DIR="release"
    ;;
  *)
    CARGO_RELEASE=0
    CARGO_PROFILE_DIR="debug"
    ;;
esac

case "$PLATFORM_NAME" in
  iphoneos)
    RUST_TARGET="aarch64-apple-ios"
    SDK_NAME="iphoneos"
    CLANG_TARGET="arm64-apple-ios26.0"
    ;;
  iphonesimulator)
    SDK_NAME="iphonesimulator"
    if [[ "$CURRENT_ARCH" == *"x86_64"* && "$CURRENT_ARCH" != *"arm64"* ]]; then
      RUST_TARGET="x86_64-apple-ios"
      CLANG_TARGET="x86_64-apple-ios26.0-simulator"
    else
      RUST_TARGET="aarch64-apple-ios-sim"
      CLANG_TARGET="arm64-apple-ios26.0-simulator"
    fi
    ;;
  *)
    echo "Unsupported iOS platform: $PLATFORM_NAME" >&2
    exit 1
    ;;
esac

SDK_PATH="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"
CLANG="$(xcrun --sdk "$SDK_NAME" --find clang)"
AR="$(xcrun --sdk "$SDK_NAME" --find ar)"

case "$RUST_TARGET" in
  aarch64-apple-ios)
    export CC_aarch64_apple_ios="$CLANG"
    export AR_aarch64_apple_ios="$AR"
    export CFLAGS_aarch64_apple_ios="-isysroot $SDK_PATH -target $CLANG_TARGET"
    export CARGO_TARGET_AARCH64_APPLE_IOS_LINKER="$CLANG"
    ;;
  aarch64-apple-ios-sim)
    export CC_aarch64_apple_ios_sim="$CLANG"
    export AR_aarch64_apple_ios_sim="$AR"
    export CFLAGS_aarch64_apple_ios_sim="-isysroot $SDK_PATH -target $CLANG_TARGET"
    export CARGO_TARGET_AARCH64_APPLE_IOS_SIM_LINKER="$CLANG"
    ;;
  x86_64-apple-ios)
    export CC_x86_64_apple_ios="$CLANG"
    export AR_x86_64_apple_ios="$AR"
    export CFLAGS_x86_64_apple_ios="-isysroot $SDK_PATH -target $CLANG_TARGET"
    export CARGO_TARGET_X86_64_APPLE_IOS_LINKER="$CLANG"
    ;;
esac

cargo_args=(
  build
  --lib
  --manifest-path "$CORE_DIR/Cargo.toml"
  --target "$RUST_TARGET"
)
if [[ "$CARGO_RELEASE" == "1" ]]; then
  cargo_args+=(--release)
fi
cargo "${cargo_args[@]}"

mkdir -p "$RUST_DIR/include"
cp "$CORE_DIR/target/$RUST_TARGET/$CARGO_PROFILE_DIR/libgoose_core.a" \
  "$RUST_DIR/libgoose_core.a"
cp "$CORE_DIR/include/goose_core_bridge.h" \
  "$RUST_DIR/include/goose_core_bridge.h"

echo "Built Goose Rust iOS library for $RUST_TARGET"
