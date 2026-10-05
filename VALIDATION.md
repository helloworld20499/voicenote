# 验证记录 · 2026-10-04

环境：本机 arm64 macOS。早期 CLI 验证使用 Apple Swift 6.2.3 和 Command Line Tools；随后已安装完整 Xcode 26.6。以下转录性能均为 Mac 测量，不代表 iPhone。

## 构建及自动检查

`swift build --product sensevoice-smoke --disable-keychain` 成功。

`swift run --disable-keychain sensevoice-smoke --check` 成功：

- 65 秒采样分段覆盖完整，没有间隙或重复；每段不超过 20 秒。
- 边界优先选择已知静音窗口；空采样输出空分段。
- 48 kHz 双声道测试音频转换成 16 kHz 单声道，时长与可用振幅保持。
- 缺失模型不能标记为就绪。

Xcode project 和 Info.plist 通过 `plutil -lint`；SwiftUI/AppModel 通过 Swift frontend 语法解析。

## 真实模型

固定权重版本：2365baeacb507f821a0c8120fcee3d484dba7a07。

INT8 文件大小：239,233,841 bytes。

模型 SHA-256：c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51。

词表 SHA-256：f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc。

App 与 CLI 使用同一下载、校验及推理代码。

官方 `test_wavs/zh.wav`，音频 5.59 秒，首次模型加载加转录约 0.57 秒，输出：

> 开饭时间早上9点至下午5点。

官方 `test_wavs/en.wav`，音频 7.15 秒，热模型约 0.12 秒，输出：

> The tribal chieftain called for the boy and presented him with 50 pieces of code.

拼接中文 + 0.5 秒静音 + 英文，音频 13.24 秒，独立进程首次加载加转录约 0.71 秒，输出：

> 开饭时间早9点至下午5点 the tribal chieftain called for the boy and presented him with5 pieces of good.

输出证明本地双语转录链路可运行；存在识别差异，不应把“非空输出”当作准确率通过。没有计算 CER/WER，没有验证句内中英混说。

## 仍需完成

在实体 iPhone 17 Pro 上验证签名安装、录音权限、超过 2 分钟录音、后台/锁屏持续录音与来电中断、播放、离线转录、文字持久化及模型下载失败恢复。测量真实耗时、峰值内存与发热。

## Xcode 安装完成后的验证

Xcode 26.6（17F113），iOS 26.5 SDK 和 Simulator runtime 安装完成。

- 修复 AppModel 缺少 SenseVoiceCore 导入的问题。
- Debug 使用 ONLY_ACTIVE_ARCH=YES，匹配模拟器上 Swift Package 的构建架构。
- 真机目标 Release 构建通过（CODE_SIGNING_ALLOWED=NO，尚未签名安装）。
- iPhone 17 Pro / iOS 26.5 模拟器 Debug 构建通过。
- swift test：7 项 XCTest 全部通过，0 失败。
- 尚未检测到连接的实体 iPhone。

## Markdown 导出验证

- 新增 4 项自动测试：时间排序与本地日期分组、中文/英文/emoji UTF-8 保留、空文字跳过与空选择错误、旧版记录 JSON 兼容；共 7 项 XCTest 通过。
- 独立 iPhone 17 Pro / iOS 26.5 模拟器使用合成记录，勾选 3 条记录，确认仅导出 2 条有文字的记录。
- 系统文件保存选择器实际保存 `声笺_2026-10-03_2026-10-04.md` 到本机 App Documents；回读文件确认日期、时间、中文、英文及 emoji 完整，无音频文件名。
- 导出仅提供 Markdown，已移除录音文件分享入口；录音仍可在 App 内播放。
- 第三方云盘未登录，尚未实测 Google Drive / OneDrive 上传。

## 长录音与后台录音更新

取消录音器与音频读取器的 120 秒限制；无需模型即可录音，停止后只保存，详情中手动转录。转录改为流式读取和重采样，再按约 15–20 秒识别，内存中的波形不随整个录音长度增长。

131 秒 48 kHz 双声道合成音频自动测试通过：总采样数、时长、单块上限、进度与可用振幅保持；共 8 项 XCTest 通过。已设置后台音频模式、录音音频会话和适配锁屏的文件保护，取消切换 App 时主动停止录音。后台、锁屏与真实来电的持续录音行为仍需实体 iPhone 验证，不能从构建成功推断已实测。

## 资料库与 Google Drive 分支

分支：`feature/record-library-google-drive`。

- 共 15 项 XCTest 全部通过：新增有效 WAV 找回、旧文字保留、删除文字后录音可播放与持久化、损坏索引不覆盖、Markdown 重名不覆盖与删除边界检查。
- Drive API 使用 URLProtocol 模拟响应，验证首次建目录、复用已建目录、UTF-8 Markdown multipart 上传（不含录音）、拒绝权限时停止上传。没有使用真实账号或伪造真实上传成功。
- GoogleSignIn-iOS 固定 9.2.0，已完成官方登录、恢复登录、增量授权、令牌刷新、账号退出和回调 URL 处理代码；Xcode workspace 保留完整依赖锁定文件。
- OAuth 配置脚本在隔离 plist 上验证 Client ID、反向 URL Scheme、重复配置不重复 URL Type，并确认后台 audio 权限保持。系统 `/usr/bin/python3` 验证通过；本机 Homebrew Python 的 plistlib/expat 有环境错误，未修改系统环境。
- 独立模拟器使用合成文字，实测「资料库 → 详情 → 保存到本机」，随后在「文件与云盘」打开 `.md` 内容；检查文字删除确认明确保留录音（未实际删除用户记录）。
- 模拟器实测选择 `Transcripts` 为常用文件夹，再从导出页直接保存到该文件夹；重名生成 `_2.md` 和 `_3.md`，回读确认中文、英文、emoji、日期与记录数完整，未覆盖原稿。
- 后台/锁屏录音继续使用 `UIBackgroundModes=audio`、`AVAudioSession.Category.record`、首次解锁后可访问文件保护；录音中进入后台不会停止或关闭音频会话。
- 仍需：真实 iOS OAuth Client ID、Google 测试账号登录与真实 Drive 上传；实体 iPhone 的后台/锁屏、来电中断与长录音验证。录音、转录和本机导出无需 Google 配置。

该分支最终 iPhone 17 Pro 模拟器 Debug 和 iPhone 设备目标 Release（未签名）构建通过；实体设备安装与录音行为尚未实测。
