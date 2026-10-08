# 历史失败签名与修法

按报错文案查表。每条都对应本仓库真实修过的提交，别重新发明解决办法。

## TestFlight 上传被拒

| 报错签名 | 成因 | 修法 |
|---|---|---|
| `90062 ... CFBundleShortVersionString [x] must contain a higher version than that of the previously approved version [x]` | 该 marketing 版本已过审上线，Apple 关闭了 train | 抬 `pubspec.yaml` 的 `version:`（如 1.0.5 → 1.0.6）后重新 push。见 `99f0394`、`373d101`、`70c79a2` |
| `90186 Invalid Pre-Release Train. The train version 'x' is closed for new build submissions` | 同上，通常和 90062 一起出现 | 同上 |
| 上传步骤前就失败、报 `altool` 找不到或签名失败 | keychain / 证书 / p12 密码类 secret 失效或过期 | 重新导出 .p12 与 App Store Connect API Key，更新 `BUILD_CERTIFICATE_BASE64` / `P12_PASSWORD` / `ASC_API_KEY_BASE64` |

注意：90062/90186 是**上传阶段**的错，构建本身是成功的。看到这两个码不要去翻 Swift / plist / 依赖。

## iOS 构建失败

| 报错签名 | 成因 | 修法 |
|---|---|---|
| Dart 编译报错（如 `const` 用法非法）导致 `flutter build ipa` 失败 | Dart 代码错误，本机 `flutter analyze` 就能发现 | 修代码。参考 `176d647` |
| `does not contain a "PrivacyInfo.xcprivacy"` / `ITMS-91053 Missing API declaration` | 用了 Required Reason API 但没声明 | 多数 Flutter 插件已自带清单（image_picker_ios / shared_preferences_foundation / webview_flutter_wkwebview / device_info_plus / package_info_plus / file_picker / in_app_purchase_storekit / share_plus）。若仍报，补 App 级 `PrivacyInfo.xcprivacy` 并挂进 Runner target。相机本身不属于 Required Reason API |
| CocoaPods 安装失败 / pod 版本冲突 | 新增或升级插件后本地没同步 | `ios/Podfile.lock` 没有入库也不是必需（CI 每次全新 `pod install`）；只有本地排查时才需要跑 `pod install` |

## Android 构建失败

| 报错签名 | 成因 | 修法 |
|---|---|---|
| `Your project's Kotlin version (x) is lower than Flutter's minimum supported version of y. Please upgrade your Kotlin version.`（发生在 `applying plugin request [id: 'dev.flutter.flutter-gradle-plugin']`） | CI 用 Flutter **latest stable**，stable 每次抬版本都会跟着抬高它强制要求的 KGP 下限；本地 Android 构建用的是同一个 stable，所以 `flutter build apk --release` 能 100% 复现 | 把 `android/settings.gradle.kts` 里 `org.jetbrains.kotlin.android` 的版本升到报错里写的下限（Flutter 3.47 → 2.2.20）。**别顺手升到 Flutter 推荐的更高版本**：KGP 2.3 起 `jvmTarget` 的字符串写法是硬错误，升之前必须先把 `app/build.gradle.kts` 的 `kotlinOptions { jvmTarget = JavaVersion.VERSION_17.toString() }` 迁成 `compilerOptions` DSL。参考 `3e6df5d`（1.9.24 → 2.1.0）、`99f0394` 之后补的 2.1.0 → 2.2.20 |
| `AAR metadata ... requires compileSdk 3x` | AGP / compileSdk 与依赖要求不匹配 | 升级 AGP 与 compileSdk。参考 `9bb9094`（AGP 8.11.1 + compileSdk 36） |
| `Namespace not specified` / `package="..."` 缺失 | 插件太旧，不兼容 AGP 8 | 升级插件。参考 `e69c3a0`（file_picker 3.0.4 → 8.3.7） |
| `mergeReleaseResources` 失败 | `res/` 目录里放了非资源文件 | 删掉。参考 `3680e45`（`res/mipmap-mdpi/README.md`） |
| release 编译期 Kotlin 报错 | Kotlin 版本过旧 | 升级 Kotlin。参考 `3e6df5d`（1.9.24 → 2.1.0） |
| `Could not download aapt2-...-windows.jar` / `Remote host terminated the handshake` | 拉 dl.google.com 的网络抖动（本地/CI 都见过） | Flutter 会自动重试一次 Gradle 构建，多数情况下第二次就过；连续失败再查网络/代理 |

Android 构建能在 Windows 本机复现，`flutter build apk --release` 跑一遍比等 CI 快得多。

`flutter build apk` 会在本地自动改 `analysis_options.yaml` / `pubspec.lock` / `android/gradle.properties`（Flutter migrator）。前两个是纯噪音、提交前 `git restore` 掉；`android/gradle.properties` 里新增的 `android.builtInKotlin=false` / `android.newDsl=false` 是 Flutter 为了兼容 AGP 9 主动加的，保留。

## 运行期才暴露、CI 完全拦不住

| 现象 | 成因 |
|---|---|
| 点「拍照」App 直接闪退 | `Info.plist` 缺 `NSCameraUsageDescription`（缺键 = 系统杀掉进程，不是弹框拒绝） |
| 点「从相册选择」闪退 | 缺 `NSPhotoLibraryUsageDescription`（iOS 15+ 走 PHPicker，通常不弹权限，但旧路径/其他能力仍需要） |
| 保存图片到相册失败 | 缺 `NSPhotoLibraryAddUsageDescription` |
| 聊天报 `400 invalid_request_error` | 服务端模型名失效（如 DeepSeek 改名）。改 `/server/config/config.toml` 的 `[llm] chat_model`，取值必须来自 `GET https://api.deepseek.com/v1/models`。参考 `734795b` |
| 请求报 `Connection refused 127.0.0.1:<port>` | 用户装过代理工具留下系统代理；App 已全局强制直连，若仍出现说明新增的出网路径没走统一 adapter |
