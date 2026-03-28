#!/usr/bin/env bash
# 生成 MNN.xcframework：iphoneos arm64 + iphonesimulator arm64（Apple Silicon 模拟器）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MNN_ROOT="${MNN_ROOT:-$ROOT/third_party/MNN}"
IOS_DIR="$ROOT/ios"
OUT_XC="$IOS_DIR/Frameworks/MNN.xcframework"
TOOLCHAIN="$MNN_ROOT/cmake/ios.toolchain.cmake"
STAGE="$MNN_ROOT/project/ios/.aiim_mnn_build"

COMMON=(
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN"
  -DMNN_METAL=ON
  -DENABLE_BITCODE=0
  -DMNN_AAPL_FMWK=1
  -DMNN_SEP_BUILD=0
  -DMNN_BUILD_SHARED_LIBS=false
  -DMNN_USE_THREAD_POOL=OFF
  -DMNN_ARM82=true
  -DMNN_LOW_MEMORY=true
  -DMNN_CPU_WEIGHT_DEQUANT_GEMM=true
  -DMNN_SUPPORT_TRANSFORMER_FUSE=true
  -DMNN_BUILD_LLM=true
)

if [[ ! -f "$MNN_ROOT/CMakeLists.txt" || ! -f "$TOOLCHAIN" ]]; then
  echo "未找到 MNN 或 cmake/ios.toolchain.cmake：$MNN_ROOT"
  exit 1
fi

rm -rf "$STAGE"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 8)"

run_cmake_build() {
  local label="$1"
  local dest="$2"
  shift 2
  local bdir="$STAGE/$label/build"
  mkdir -p "$bdir"
  ( cd "$bdir" && cmake "$MNN_ROOT" "$@" && cmake --build . --target MNN -j"$JOBS" )
  local fwk
  fwk="$(find "$bdir" -maxdepth 5 -name 'MNN.framework' -type d | head -1)"
  if [[ -z "$fwk" ]]; then
    echo "未在 $bdir 找到 MNN.framework"
    exit 1
  fi
  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest"
  cp -R "$fwk" "$dest"
}

run_cmake_build device "$STAGE/device/MNN.framework" "${COMMON[@]}" -DPLATFORM=OS64 -DARCHS=arm64
run_cmake_build sim "$STAGE/sim/MNN.framework" "${COMMON[@]}" -DPLATFORM=SIMULATOR64 -DARCHS=arm64

mkdir -p "$IOS_DIR/Frameworks"
rm -rf "$OUT_XC"
xcodebuild -create-xcframework \
  -framework "$STAGE/device/MNN.framework" \
  -framework "$STAGE/sim/MNN.framework" \
  -output "$OUT_XC"

echo "已安装: $OUT_XC"
