# android-native-IM-ai

一个 **局域网 IM 聊天 + 端侧离线 AI 问答** 示例项目：包含 **Android 原生**（Kotlin + Jetpack Compose）与 **Flutter 跨端客户端**（`lib/`、`ios/`），两端共享相近的 IM 与 MNN 端侧能力。

- **局域网 IM**：同一 Wi‑Fi 下点对点 TCP Socket 通信（设备 A 当服务器，设备 B 连接 IP）。
- **端侧 AI（MNN LLM）**：模型不随应用包提供，首次由用户从云存储下载到本地，之后离线问答；支持模型选择、下载确认与进度提示；内置“温柔女孩”人设（soul）。

## 克隆后必看：`.gitignore` 与功能对应关系

以下路径**刻意不入库**（体积、密钥或可由脚本生成）。缺失时会导致对应能力不可用，请按后文各节在本机补齐。

| 忽略项 | 影响 |
|--------|------|
| `third_party/MNN/` | **Android JNI 编译**与 **iOS 本地编 MNN.xcframework** 都需要 MNN 源码/头文件树；缺失则无法完成带端侧 MNN 的原生构建。 |
| `ios/Frameworks/MNN.xcframework/` | **iOS 端侧 MNN** 链接失败或 Xcode「Check MNN.xcframework」阶段报错；需本地构建后放入（见下文）。 |
| `android/.../jniLibs/**/*.so` | **Android** 若未通过 Gradle 自动下载 MNN 预编译库，则端侧推理不可用，需手动放置 `.so`。 |
| `tools/pc-ai-server/.env` | 仅影响 **PC AI 桥接**（Ollama/OpenAI）；复制 `.env.example` 为 `.env` 即可，与端侧 MNN 无关。 |
| `ios/Pods/`（由 `ios/.gitignore` 忽略） | 克隆后需在 `ios/` 下执行 **`pod install`**，否则无法打开 Workspace 或编译 iOS。 |

## 克隆后必做：MNN 头文件目录 `third_party/MNN`

仓库根目录下的 **`third_party/MNN/` 不会随 Git 上传**（已在 `.gitignore` 中忽略，避免把整棵 MNN 源码树推进本仓库）。

### 没有它会怎样？

- **Android 端若需编译 JNI（`libaiim_mnn_jni.so`）**：CMake 会检查 `third_party/MNN/include/MNN/Interpreter.hpp` 等头文件；**缺失则配置阶段直接失败**，无法完成带端侧 MNN 的 Android 构建，**端侧推理能力不可用**。
- 配置入口见：`android/app/src/main/cpp/CMakeLists.txt`。

### 如何在本机补充（任选一种）

在**仓库根目录**执行。

**Windows（推荐，与仓库脚本一致）**：

```powershell
powershell -ExecutionPolicy Bypass -File tools/setup_mnn_headers.ps1
```

**macOS / Linux**：

```bash
mkdir -p third_party
git clone --depth 1 --filter=blob:none --sparse -b 3.4.1 https://github.com/alibaba/MNN.git third_party/MNN
cd third_party/MNN
git sparse-checkout set include transformers/llm/engine/include
cd ../..
```

成功后应存在文件：`third_party/MNN/include/MNN/Interpreter.hpp`。需要已安装 **Git**，且能访问 GitHub。

### 预编译 `.so`（同样未入库）

`android/app/src/main/jniLibs/arm64-v8a/` 下的 **`libMNN.so` 等预编译库默认也不提交**。首次构建 Android 时，`android/app/build.gradle.kts` 中的 Gradle 任务会尝试从网络下载 MNN 发行包并拷贝到 `jniLibs`；若下载失败，需自行按该文件中的说明准备 `.so`。

### iOS：`MNN.xcframework`（未入库）

**`ios/Frameworks/MNN.xcframework/` 被忽略**，体积大且需与本地 Xcode 工具链一致编译。没有它则 **iOS 端侧 MNN 无法链接/编译**（工程内已配置链接该 XCFramework）。

1. 先按上文准备好 **`third_party/MNN/`**（完整源码树，不仅是 sparse 头文件；构建脚本需要 `CMakeLists.txt` 等）。
2. 在仓库根目录执行：

```bash
bash tools/build_mnn_ios.sh
```

3. 将生成的 **`MNN.xcframework`** 放到 **`ios/Frameworks/`**（与 `ios/Frameworks/PLACE_MNN_FRAMEWORK_HERE.txt` 说明一致）。
4. 在 **`ios/`** 目录执行 **`pod install`**，用 **`ios/Runner.xcworkspace`** 打开工程；Flutter 侧可用 `flutter run -d ios`。

若仅需跳过本地检查（例如尚未放入 framework），可在 Xcode 构建环境变量中设置 **`AIIM_SKIP_MNN_CHECK=1`**（仍无法在缺少库的情况下真正链接成功）。

## 项目特性

- 局域网通信：一台设备启动服务端，另一台设备通过 IP 连接
- 即时聊天：支持文本消息收发
- 连接状态：连接中、已连接、断开、失败等状态反馈
- 心跳机制：定时心跳包，降低静默断连不可见的问题
- 本地存储：使用 Room 持久化消息记录
- 底部导航：`首页` + `聊天室` + `我的`
- 个人资料：支持编辑头像、邮箱、用户名、性别、电话，并本地缓存
- 聊天室历史：每次进入聊天室都会创建会话，并按会话保存对应消息到本地
- 发送状态：发送中/已发送/已送达/已读/失败（含回执消息）
- AI 聊天：端侧 MNN 模型离线问答（需要先下载模型）
- 模型管理：选择模型 → 确认下载 → 下载进度条 → 下载完成后可离线使用
- 人设（soul）：默认“温柔女孩版”提示词，自动注入每次问答
- 现代架构：Compose UI + ViewModel + Hilt + Coroutines

## 技术栈

- Kotlin 1.9.22
- Android Gradle Plugin 8.2.0
- Jetpack Compose
- Hilt
- Room
- Gson
- Timber
- SharedPreferences（个人信息本地缓存）

## 运行环境

- Android Studio（建议最新稳定版）
- JDK 17
- Android SDK：
  - `compileSdk = 34`
  - `targetSdk = 34`
  - `minSdk = 24`

## 快速开始

1. 克隆项目并使用 Android Studio 打开根目录
2. 等待 Gradle 同步完成
3. 连接两台安卓设备（或两台模拟器）到同一局域网
4. 分别安装并启动应用
5. 在设备 A：
   - 进入连接页后点击“启动服务器”（监听端口 `8080`，见 `Constants.SOCKET_PORT`）
   - 记录页面展示的本机 IP（局域网 IPv4）
6. 在设备 B：
   - 输入设备 A 的 IP
   - 点击“连接服务器”（App 里默认端口为 `8080`）
7. 连接成功后，双方进入聊天室收发消息
8. 切换到底部 `我的` 页面可编辑并保存个人资料（保存在本地）
9. 切换到底部 `聊天室` 页面可查看历史聊天室并进入查看对应消息

### 端侧 AI（MNN LLM）使用

AI 模型 **不随 APK 提供**，必须先下载后才能问答：

1. 进入 `AI聊天` 页面，点击右上角 **「切换模型」**
2. 选择模型（当前只有 `qwen3.5`）→ **确认**
3. 弹框提示是否下载 → 点击 **下载**
4. 等待进度完成后即可离线问答

#### 模型云存储目录约定（必看）

模型文件存放在：

- `https://oss-mnn.obs.cn-south-1.myhuaweicloud.com/mnn/{modelId}/`

例如：`qwen3.5` 对应目录 `…/mnn/qwen3.5/`，并且至少包含：

- **必需**：`config.json`、`tokenizer.txt`
- **必需**：`config.json` 中指定的 `llm_model` 与 `llm_weight`（例如 `llm.mnn`、`llm.mnn.weight`）
- **可选**（没有会跳过）：`llm_config.json`、`configuration.json`、`llm.mnn.json`、`visual.mnn`、`visual.mnn.weight`

代码位置：`app/src/main/java/com/aiim/android/data/ai/MnnOnDeviceQaEngine.kt`

### 手机与 PC AI 对聊（可选）

如果你想让另一端回复 AI（Ollama 或 OpenAI 兼容服务），请在 PC 端启动 `tools/pc-ai-server`。

1. 安装并启动 Ollama（示例）
   - 执行：`ollama serve`
   - 拉模型：`ollama pull llama3.2`（或替换为你自己的模型）
   - 用：`ollama list` 查看准确的模型名（与配置里的 `AIIM_OLLAMA_MODEL` 一致）
2. 配置 `tools/pc-ai-server/.env`
   - 主要控制项：
     - `AIIM_BACKEND`：`ollama` 或 `openai`
     - `AIIM_OLLAMA_URL` / `AIIM_OLLAMA_MODEL`
     - `AIIM_OPENAI_BASE_URL` / `AIIM_OPENAI_MODEL`
     - `AIIM_HOST` / `AIIM_PORT`：监听地址与端口（默认端口 `8080`，与 App 一致）
3. 启动 PC AI 桥接服务
   - 在项目根目录执行：`python .\tools\pc-ai-server\server.py`
   - 该桥接服务与 App 使用同一行协议：Android 一次只维持一条 TCP 连接，适合「手机 <-> PC AI」单会话；如要多会话需要后续扩展。
4. Android 端连接 PC
   - 打开 App 的 `首页`（连接页）
   - 点击“连接服务器”
   - `IP` 填 PC 的局域网 IPv4 地址（端口保持 `8080`）
   - 连接成功后进入聊天室即可开始对话

## 构建命令

在项目根目录执行：

```bash
./gradlew assembleDebug
```

Windows 下：

```powershell
.\gradlew.bat assembleDebug
```

### 产物位置（常用）

- Debug APK：`app/build/outputs/apk/debug/app-debug.apk`
- Release（未签名）APK：`app/build/outputs/apk/release/app-release-unsigned.apk`

## 目录结构（核心）

```text
app/src/main/java/com/aiim/android
├─ core/        # 基础能力（Socket、工具类、常量）
├─ data/        # 数据层（Room、Repository、Mapper）
├─ domain/      # 领域层（Model、Repository 抽象、UseCase）
├─ di/          # Hilt 依赖注入模块
└─ ui/          # Compose 页面、组件、ViewModel
```

## 使用说明

- 请确保两台设备在同一个局域网（同一个 Wi-Fi）
- 输入 IP 时请使用对端设备在局域网内的 IPv4 地址
- 头像与个人资料数据保存在本机本地缓存，不会自动上传
- 聊天室历史逻辑：从 `首页` 进入聊天室时会自动创建一个会话，并把后续该会话内的消息归档；在 `聊天室` Tab 可点击历史会话查看对应消息。
- 数据库版本升级时当前使用了“破坏性迁移”（`fallbackToDestructiveMigration()`），因此升级大版本可能会清空本地聊天数据。
- 若连接失败，优先检查：
  - 两台设备网络是否互通
  - 对端是否已点击“启动服务器”
  - 网络策略是否限制了局域网通信
- AI 无法问答时，优先检查：
  - 是否已在 `AI聊天` → `切换模型` 完成下载（未下载会直接提示）
  - OSS 目录下是否已上传 `config.json` / `tokenizer.txt` / `llm_model` / `llm_weight`
  - 网络/DNS 是否可用（下载阶段会显示中文错误提示）

## 当前状态与计划

当前已完成：局域网 IM 基础通信与聊天能力。  
并已支持底部导航与本地个人资料管理。  
并已支持端侧 AI 模型下载、选择与离线问答。  
后续可扩展方向：

- AI：更多模型管理（多模型列表、清理模型、下载重试/断点续传）
- 多设备发现（mDNS / 局域网广播）
- 文件/图片消息
- 聊天记录管理（删除、导出、检索）

## 许可证

本项目采用 [MIT License](./LICENSE)。
