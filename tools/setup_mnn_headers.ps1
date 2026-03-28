# 拉取 MNN 3.4.1 头文件（供 Android CMake 编译 libaiim_mnn_jni.so）
# 在仓库根目录执行: powershell -ExecutionPolicy Bypass -File tools/setup_mnn_headers.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (Test-Path "third_party/MNN/include/MNN/Interpreter.hpp") {
  Write-Host "third_party/MNN 已存在，跳过。"
  exit 0
}

New-Item -ItemType Directory -Force -Path "third_party" | Out-Null
if (Test-Path "third_party/MNN") {
  Remove-Item -Recurse -Force "third_party/MNN"
}

git clone --depth 1 --filter=blob:none --sparse -b 3.4.1 https://github.com/alibaba/MNN.git third_party/MNN
Set-Location third_party/MNN
git sparse-checkout set include transformers/llm/engine/include
Set-Location $root
Write-Host "完成: third_party/MNN"
