pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    // Flutter stable 会随时抬高最低支持的 KGP 版本（Flutter 3.47 起硬下限
    // 是 2.2.20），低于下限会在 apply flutter-gradle-plugin 时直接构建失败。
    // 注意：升到 2.3.x 之前必须先改 app/build.gradle.kts —— KGP 2.3 起
    // 字符串形式的 jvmTarget 是硬错误，要迁到 compilerOptions DSL。
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
