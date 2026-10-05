# Google Drive 直传配置

本 App 使用 Google 官方 GoogleSignIn-iOS 9.2.0 和 Drive API v3。无需你另建服务器，也不需要在 iPhone 安装 Google Drive App。需要先在 Google Cloud 创建属于本 App 的 **iOS OAuth Client ID**。未配置前，App 会显示「Google Drive 待配置」，本机录音、转录和 Markdown 导出仍可使用。

## 1. 创建项目并启用 Drive API

1. 打开 [Google Cloud Console](https://console.cloud.google.com/)，登录自己的 Google 账号。
2. 选择已有项目或创建一个项目。
3. 进入「API 和服务 → 库」，搜索 **Google Drive API** 并启用。

## 2. 配置 Google Auth Platform

在项目中进入 Google Auth Platform（部分界面仍称 OAuth 同意屏幕）：

1. Branding：填应用名称「声笺」、用户支持邮箱与开发者联系邮箱。
2. Audience：个人测试通常选择 External，并保持 Testing；添加自己用于登录 Drive 的邮箱为测试用户。Workspace 内部项目则按组织要求选择 Internal。
3. Data Access：添加 `https://www.googleapis.com/auth/drive.file`。

App 只请求操作自己创建的文件和目录，不请求读取整个云盘。官方登录 SDK 还会请求登录所需的基本身份范围。该版固定保存到「我的云端硬盘 / 声笺」，不会浏览任意已有目录；如要选自定义目录，可使用 App 的「常用保存文件夹」或系统保存入口。

## 3. 创建 iOS Client ID

1. 在 Clients（或「API 和服务 → 凭据」）中新建 OAuth Client ID。
2. 应用类型选择 **iOS**，不要选择 Web 或 Android。
3. Bundle ID 填 Xcode target 当前的 Product Bundle Identifier，默认是 `com.local.sensevoiceprototype`。如果改过，必须填修改后的值。
4. Apple Team ID 按控制台要求填写 Xcode Signing & Capabilities 中你的开发团队 ID。暂未上架时按控制台当前要求处理 App Store ID。
5. 创建后复制以 `.apps.googleusercontent.com` 结尾的 Client ID。无需 Client Secret、服务账号或私钥。

## 4. 写入 App 配置

在项目目录运行：

```sh
/usr/bin/python3 Scripts/configure_google.py '你的iOSClientID.apps.googleusercontent.com'
```

脚本会在 `SenseVoiceApp/Info.plist` 写入 `GIDClientID` 与对应的反向 URL Scheme，不修改后台音频权限或其他已有 URL Scheme。这个 Client ID 是公开的客户端标识，可随 App 分发；不要把访问令牌、私钥或服务账号凭据提交进 Git。

重新在 Xcode 构建安装。打开 App「文件与云盘」，点击 Google 登录按钮，使用测试用户账号登录并允许 Drive 权限。

## 5. 验证上传

1. 准备一条有文字的记录，点「导出文字到文件 / 云盘」。
2. 点「上传到 Google Drive」。初次登录授权后创建 `声笺` 文件夹并上传一个 `.md` 文件。
3. 点「查看 Google Drive 文件」，检查日期、中文、英文及换行。录音不上传。
4. 再上传另一份稿件，确认仍保存到同一文件夹。
5. 断网重试，确认显示错误，录音和转录文字仍在本机；恢复网络后手动重试。
6. 「文件与云盘 → 断开账号」会清除本 App 的登录状态，不删除云盘文件。需要彻底撤销授权可在 Google 账号的第三方应用连接页面操作。

同名上传会新建文件，不覆盖之前的版本。删除 App 本机文字或文件不删除已上传的云盘副本。本版不做自动同步或后台上传；上传过程中请保持 App 在前台。

## 常见问题

- 无法登录 / 客户端不匹配：确认使用 iOS Client ID、Bundle ID 一致、重新运行配置脚本后已构建安装新版本。
- 403：检查 Drive API 已启用、测试邮箱已添加、已允许 `drive.file`、Workspace 管理策略以及云盘存储空间。
- Testing 状态可能导致授权会话较短，到期后重新登录即可；正式面向其他人分发前，完成 Google 的发布与验证要求。
- 目前只有请求模拟测试与构建验证；未配置真实 Client ID 前，不能声称已验证账号登录或真实上传。

官方参考：[iOS 登录配置](https://developers.google.com/identity/sign-in/ios/start-integrating)、[访问 Google API](https://developers.google.com/identity/sign-in/ios/api-access)、[Drive 权限范围](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)、[Multipart 上传](https://developers.google.com/workspace/drive/api/guides/manage-uploads)。
