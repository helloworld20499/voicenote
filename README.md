# 声笺 · SenseVoice iPhone 原型

原生 SwiftUI App，面向 iPhone 17 Pro 测试。先保存录音，需要时使用 SenseVoice Small INT8 在设备上转录。没有服务器、账号或转录 API。

## 现在可以试什么

- 第一次联网下载约 239 MB 的模型与词表，显示进度并校验 SHA-256；之后离线运行。
- 录音无两分钟上限；停止后保存音频，可稍后手动转录。未下载模型也可录音。
- 已配置后台和锁屏录音；从前台开始录音后可切换 App 或锁屏，待真机验证。
- 自动识别语言，启用标点和逆文本规范化，测试中文夹英文。
- 保存录音与文字；播放、编辑、复制、分享、删除，以及失败后重新转录。
- 仅导出 Markdown（.md）文字：单条、多选、今天或全部，按日期和时间合并；不导出录音。
- 手动选择保存到本机，或「文件」App 中已启用的 iCloud Drive、Google Drive、OneDrive 等位置。
- 显示音频时长和实际转录耗时，方便在 iPhone 上评估。
- 来电/音频中断后停止并保存录音，不自动恢复。切换 App 不主动停止录音。

## 在 iPhone 17 Pro 上安装

本机已安装 Xcode 26.6 和 iOS 26.5 平台组件。原型已通过 iPhone Release（未签名）与 iPhone 17 Pro 模拟器 Debug 构建。尚未在实体 iPhone 上安装或测试。

1. 安装支持 iPhone 当前 iOS 版本的完整 Xcode（iOS 26 使用 Xcode 26 或更新的兼容版本），启动并完成必要组件安装。
2. 打开 `SenseVoicePrototype.xcodeproj`。等待 Swift Package Manager 下载依赖；模型不会随着依赖下载，它由手机 App 首次启动后下载。
3. Xcode → Settings → Accounts 添加 Apple Account。
4. 选择 `SenseVoicePrototype` target → Signing & Capabilities → Team 选择自己的团队。如 Bundle Identifier 冲突，改为自己的唯一标识。
5. 用 USB 连接 iPhone，信任 Mac；如设备要求，按提示开启 Developer Mode。
6. 选择 iPhone 17 Pro 为运行设备，点击 Run。性能测试建议将 scheme 的 Run 配置改为 Release。
7. 允许麦克风权限，录制一段 10–30 秒的中英文混说，点击“停止并保存”。转录前点击“下载 SenseVoice 模型”，再到录音详情点击“转录这段录音”。
8. 开启飞行模式，重复录音，确认离线转录；在“资料库”查看音频和文字。

免费 Apple Account 可用于个人设备测试，但通常需每 7 天重新签名安装。TestFlight/App Store 分发需要 Apple 开发者会员。

## 导出给 AI

在「资料库」点「选择」，勾选记录，再点「导出文字」。可直接保存到本机、常用文件夹或 Google Drive，也可使用「另选保存位置」打开系统选择器。右上角菜单支持今天/全部文字，记录详情支持单条。

输出一个 UTF-8 `.md` 文件，按本机时区记录日期与时间，保留已保存或编辑过的文字；跳过暂无文字的记录。只保存 Markdown，不提供 TXT 或录音导出。本机导出文件在「文件与云盘」中可查看、分享和删除。可上传这个文件给 AI；保存到云盘本身不会自动让 AI 获得访问权限。

Google Drive 直接上传需先配置 iOS OAuth Client ID，详见 [GOOGLE_DRIVE_SETUP.md](GOOGLE_DRIVE_SETUP.md)。本机录音和导出无需 Google 配置。真实 Google 登录和上传仍需配置后验证。

## 第一轮真机测试建议

1. 清晰中文：读一段带数字和日期的话。
2. 英文：读两句话。
3. 中英混说：例如“我在 iPhone 17 Pro 上测试这个 API，timeout 设置成 thirty seconds。”
4. 录制 40–60 秒跨分段的内容，检查断句位置是否漏字。
5. 转录完成后关闭并重开 App，确认录音与编辑过的文字仍在。
6. 录制超过 2 分钟，期间切换 App 并锁屏；返回后停止，检查播放时长和声音连续性，再手动转录。
7. 录音中接听来电，确认中断前音频可播放，且没有自动重新录音。

目前只有最简单的按低能量位置分段，最长每段约 20 秒，不是神经网络 VAD，不是连续实时字幕。人名、术语、中英切换、噪声以及分段边界需要实际测试。首次加载模型可能比后续转录慢。

## 已完成的验证

- 核心 Swift package 在本机 arm64 macOS 编译、链接成功。
- 真实模型下载、完整性校验、中文/英文官方样本转录成功。
- 中文接英文的拼接样本可生成含两种语言的文字，但观察到词语和数字错误；这不等同于句内混说准确率验证。
- 65 秒音频的分段覆盖、无间隙/重复、安静位置选择、空输入、48 kHz 立体声→16 kHz 单声道重采样、缺失模型检查通过。
- Xcode 工程 plist 和 App Info.plist 格式检查通过，iOS UI 源码语法解析通过。
- Xcode 26.6：iPhone Release（未签名）构建成功；iPhone 17 Pro 模拟器 Debug 构建成功。
- 完整 Xcode 环境下 `swift test` 的 15 项核心、存储与导出 XCTest 测试全部通过。
- 131 秒、48 kHz 双声道合成音频已验证分块读取和重采样，所有样本覆盖，每个推理块不超过 20 秒。
- **未验证：设备签名、麦克风真机行为、后台/锁屏录音、iPhone 17 Pro 性能/发热。**

CLI 验证（无需完整 Xcode）：

```sh
cd /Users/ericcartman/Documents/workspace/Projects/sensevoice-ios
swift run --disable-keychain sensevoice-smoke --check
swift run --disable-keychain sensevoice-smoke Artifacts/Models Artifacts/zh.wav Artifacts/en.wav
```

`--disable-keychain` 用于绕过本机 SwiftPM 查询公共下载凭据时的 Keychain 错误，不需要 GitHub 凭据。`Tests/CoreTests.swift` 是 XCTest 版本，目前已在完整 Xcode 环境中通过 `swift test --disable-keychain`；命令行开发目录未切换时可在命令前加 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

详见 `VALIDATION.md`。

## 文件与隐私

- 手机 `Documents/Recordings/`：WAV 和 `recordings.json`；本原型关闭该目录的系统备份。
- 手机 `Application Support/SenseVoicePrototype/Models/`：模型和词表；模型可重新下载，不参与备份。
- 只在模型下载时访问 Hugging Face/CDN。录音与推理不调用网络。
- 文字分享使用 iOS 分享面板；Markdown 导出使用系统文件保存选择器，由用户主动选择目标。
- 云盘需要安装、登录对应 App，并在「文件」App 中启用；上传和同步由云盘 App 负责。
- 没有语音合成、摘要或说话人分离。

## 实现

- `SenseVoiceApp/`：SwiftUI 界面、录音与本地记录管理。
- `Core/`：模型下载校验、音频重采样、分段和 SenseVoice 推理。
- `Package.swift`：固定 sherpa-onnx 源码版本；间接使用 ONNX Runtime 的预编译二进制。
- `Smoke/`：独立检查和真实音频验证工具。
- `THIRD_PARTY_NOTICES.md`：依赖来源；发布前确认具体模型权重许可并附全依赖许可。

模型来源： https://k2-fsa.github.io/sherpa/onnx/sense-voice/pretrained.html

## Git 与项目维护

仓库保存源码、Xcode 工程、共享 scheme、依赖锁定文件及验证说明。模型、测试音频、录音、构建产物和本机配置不提交。克隆后打开 `SenseVoicePrototype.xcodeproj`，由 Swift Package Manager 获取依赖，模型仍由 App 首次下载。

`Scripts/generate_project.py` 保留工程生成脚本；仅在需要重新生成工程时运行 `python3 Scripts/generate_project.py`。它会覆盖工程配置，Xcode 中手动调整签名后无需运行。

## 后台录音实现

`UIBackgroundModes=audio` 和 `AVAudioSession.Category.record` 用于持续录音。音频文件与索引使用首次解锁后可访问的文件保护，支持当前录音跨锁屏写入。开始录音仍须在前台明确操作并授权麦克风；停止后释放音频会话。来电等系统中断保存当前录音，不自动恢复。强制退出、崩溃或关机后的录音恢复尚未实现。

转录在前台手动启动，按约 15–20 秒逐块读取、重采样和识别，不一次加载整段长录音。转录不会删除原音频。后台音频权限不用于维持后台 AI 推理；长转录时请保持 App 在前台。

## 资料库和保存位置

停止录音后直接进入新记录详情，录音使用带日期的文件名。资料库顶部可切换「全部录音」与「转录稿」，下拉可刷新并找回有效但尚未入库的 WAV。无法解析的原有索引不会被静默覆盖。录音文件可从系统「文件 → 我的 iPhone → 声笺 → Recordings」找到。

转录稿可在详情或「转录稿」列表中单独删除，保留原始录音以便重转录。「文件与云盘」管理手动导出到本机 `Transcripts` 的 `.md` 副本，删除副本不会删除录音或资料库文字。删除文字或本机副本都不会删除已上传的云盘文件。

常用文件夹选择一次后保存书签，后续直接保存；文件提供商不支持文件夹选择时使用系统保存入口。Google Drive 使用独立的官方登录和上传流程，固定上传到该 App 创建的「声笺」文件夹，仅请求 `drive.file` 范围，详见配置说明。
