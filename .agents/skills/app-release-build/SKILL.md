---
name: app-release-build
description: 喜宽 App（Flutter，仓库 aiquant）iOS/Android 的打包发布前检查与失败排查。push 到 main 会自动构建并上传 TestFlight，所以发版相关改动必须先过这里的版本号与构建检查；也用于排查 iOS/Android workflow 报错。
metadata:
  short-description: 发版前的版本号闸门与打包检查
---

# 喜宽发版构建

push 到 `main` 或打 `v*` tag 会自动触发两个 workflow，**不需要手动跑构建**，但也意味着任何一次 push 都是一次真实发版尝试：

| workflow | 产物 | 后续动作 |
|---|---|---|
| `.github/workflows/ios-testflight.yml` | `build/ios/ipa/喜宽.ipa` | 上传 TestFlight（`apple-actions/upload-testflight-build@v3`） |
| `.github/workflows/android-build.yml` | `app-release.apk` | 只上传为 Actions artifact，不发 Play |

两端都用 `--build-number=$((100 + github.run_number))`，并注入 `--dart-define=API_BASE_URL=https://api.singzquant.com`。

workflow 没有 `paths` 过滤，**任何一次 push 到 main 都会重新打包**（改文档、改 skill 也算），iOS 那条还会真的往 TestFlight 传一个构建。所以：改完文案/文档类内容要不要立刻 push，先想清楚会不会白烧一轮 CI 和一个 TestFlight 构建；确实不需要时可以等和下一次代码改动一起推。

## 第一优先：TestFlight 的版本号闸门

这是本仓库最容易踩、也最容易被误判成"代码问题"的失败：

- `CFBundleShortVersionString` 取自 `pubspec.yaml` 里 `version:` 的 `+` **前面**那段（如 `1.0.6+1` → `1.0.6`）。`+` 后面那段只影响本地构建，CI 里会被 `--build-number` 覆盖。
- 某个版本一旦在 App Store 过审上线，Apple 就关闭该 train，之后提交**同号或更低**的构建都会被拒，报错码 `90062`（must contain a higher version than previously approved）和 `90186`（Invalid Pre-Release Train，train closed）。

所以改动 App 后准备 push 到 main 之前，先确认：**当前 `pubspec.yaml` 的 marketing 版本是否已经上线过？** 是，就必须抬号（如 `1.0.5` → `1.0.6`），并且在 commit message 里写明原因，例如 `build(ios): 版本号升至 1.0.6 (1.0.5 train 已关闭, TestFlight 拒绝 90062/90186)`。仓库历史上 `1.0.1 / 1.0.2 / 1.0.6` 都是因为这个原因抬的。

判断依据：App Store Connect 里该版本的构建是否已被批准；或者看报错文案里的 `previously approved version [x.y.z]`。

## push 前的检查清单

1. `flutter analyze` 无色（Dart 编译错误会让 iOS / Android 两端一起挂，本地能拦住）。
2. 版本号闸门（上一节）——只有"要发新版本"时才抬，纯文档/后端改动不用抬。
3. 新增了系统能力就补齐 `ios/Runner/Info.plist` 的用途说明。**缺 `NSCameraUsageDescription` 这类键不会导致构建失败，但用户一点就崩**，所以 CI 拦不住，只能靠这里。当前已声明：相机、相册读、相册写、文件。
4. Android 侧能在 Windows 本机验证：至少跑一次 `flutter build apk --release`。iOS 只能在 CI 上验证（本机没有 macOS）。
5. 涉及 Kotlin / AGP / compileSdk / 插件大版本时单独评估。最常复发的是 **Flutter stable 抬高 Kotlin 硬下限**：CI 用 latest stable，本地也是同一个 stable，所以 `flutter build apk --release` 能提前复现，别等 CI。其余签名见 [references/ci-failures.md](references/ci-failures.md)。

## CI 拦不住、但会影响发版的两件事

- **App 隐私问卷**：只要新功能把用户数据传到服务端并落库（例如图片上传 → `ai_chat_messages.images_json`），App Store Connect 的 App 隐私里就要补对应数据类型（照片上传属于「用户内容 → 照片或视频」，用途 App 功能、与身份关联、不用于追踪）。
- **审核备注**：App 主要功能需要登录（手机号/邮箱验证码，mock 环境下验证码打日志）。给审核员留一个可用测试账号，并在备注里说明核心功能，否则容易被拒。

## 相关 GitHub Secrets

iOS：`TUSHARE_TOKEN`、`DEEPSEEK_API_KEY`（两端都要，缺了 workflow 直接 `::error::` 退出）、`ASC_API_KEY_ID`、`ASC_API_ISSUER_ID`、`ASC_API_KEY_BASE64`、`BUILD_CERTIFICATE_BASE64`、`P12_PASSWORD`、`KEYCHAIN_PASSWORD`。Android 只用前两个。

## 排查

上传/构建失败的报错签名、成因和修法见 [references/ci-failures.md](references/ci-failures.md)。
