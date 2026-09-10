pluginManagement {
    val flutterSdkPath =
        run {
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
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
include(":app:node_feature")
project(":app:node_feature").projectDir = file("app/src/node_feature")
include(":app:python_feature")
project(":app:python_feature").projectDir = file("app/src/python_feature")
include(":app:java_feature")
project(":app:java_feature").projectDir = file("app/src/java_feature")
include(":app:kotlin_feature")
project(":app:kotlin_feature").projectDir = file("app/src/kotlin_feature")
include(":app:clang_feature")
project(":app:clang_feature").projectDir = file("app/src/clang_feature")
include(":app:dart_feature")
project(":app:dart_feature").projectDir = file("app/src/dart_feature")
include(":app:ty_feature")
project(":app:ty_feature").projectDir = file("app/src/ty_feature")
include(":app:rust_analyzer_feature")
project(":app:rust_analyzer_feature").projectDir = file("app/src/rust_analyzer_feature")
include(":app:gopls_feature")
project(":app:gopls_feature").projectDir = file("app/src/gopls_feature")
include(":app:emmylua_feature")
project(":app:emmylua_feature").projectDir = file("app/src/emmylua_feature")
include(":app:bash_language_server_feature")
project(":app:bash_language_server_feature").projectDir = file("app/src/bash_language_server_feature")
include(":app:copilot_language_server_feature")
project(":app:copilot_language_server_feature").projectDir = file("app/src/copilot_language_server_feature")
include(":app:kmp_lsp_feature")
project(":app:kmp_lsp_feature").projectDir = file("app/src/kmp_lsp_feature")
include(":app:vscode_langservers_extracted_feature")
project(":app:vscode_langservers_extracted_feature").projectDir = file("app/src/vscode_langservers_extracted_feature")
include(":app:rust_feature")
project(":app:rust_feature").projectDir = file("app/src/rust_feature")
include(":app:go_feature")
project(":app:go_feature").projectDir = file("app/src/go_feature")
include(":app:ruby_feature")
project(":app:ruby_feature").projectDir = file("app/src/ruby_feature")
include(":app:lua_feature")
project(":app:lua_feature").projectDir = file("app/src/lua_feature")
