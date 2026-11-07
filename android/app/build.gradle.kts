import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

//-----------------------------------------------------------------------
// Debug-only: bundle every *_feature module's assets and jniLibs into the
// base APK so they work without Play delivery.

val onlyFeatures = (project.findProperty("debugFeatures") as String?)
    ?.split(",")?.map { it.trim() + "_feature" }

val featureDirs = file("src").listFiles { f ->
    f.isDirectory && f.name.endsWith("_feature") &&
        (onlyFeatures == null || f.name in onlyFeatures)
}?.sortedBy { it.name }.orEmpty()

val debugBundles = layout.buildDirectory.dir("generated/debug_bundles")
val stageDebugBundles by tasks.registering(Copy::class) {
    featureDirs.forEach { dir ->
        from(File(dir, "src/main/assets")) { include("*.zip") }
    }
    into(debugBundles.map { it.dir("flutter_assets/debug_bundles") })
}

val debugJniLibs = layout.buildDirectory.dir("generated/debug_jnilibs")
val stageDebugJniLibs by tasks.registering(Copy::class) {
    duplicatesStrategy = DuplicatesStrategy.EXCLUDE // first copy wins
    featureDirs.forEach { from(File(it, "src/main/jniLibs")) }
    into(debugJniLibs)
}
// -----------------------------------------------------------------------

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.roxum"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    // -----------------------------------------------------------------
    sourceSets {
        getByName("debug") {
            assets.srcDir(debugBundles.get().asFile)
            jniLibs.srcDir(debugJniLibs.get().asFile)
        }
    }
    // -------------------------------------------------------------------

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.roxum"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters.add("arm64-v8a")
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            pickFirsts += listOf(
                "lib/arm64-v8a/libc++_shared.so",
                "lib/arm64-v8a/libandroid-execinfo.so",
            )
            excludes += setOf("**/armeabi-v7a/**", "**/x86_64/**")
        }
    }

    dynamicFeatures.addAll(
        setOf(
            ":app:rust_feature",
            ":app:zig_feature",
            ":app:go_feature",
            ":app:ruby_feature",
            ":app:lua_feature",
            ":app:node_feature",
            ":app:python_feature",
            ":app:java_feature",
            ":app:kotlin_feature",
            ":app:clang_feature",
            ":app:dart_feature",
            ":app:ty_feature",
            ":app:rust_analyzer_feature",
            ":app:zls_feature",
            ":app:gopls_feature",
            ":app:emmylua_feature",
            ":app:bash_language_server_feature",
            ":app:copilot_language_server_feature",
            ":app:kmp_lsp_feature",
            ":app:vscode_langservers_extracted_feature",
        )
    )
}

// ----------------------------------------------------------------
tasks.configureEach {
    if (name.startsWith("merge") && name.endsWith("DebugAssets")) {
        dependsOn(stageDebugBundles)
    }
    if (name.endsWith("DebugJniLibFolders")) {
        dependsOn(stageDebugJniLibs)
    }
}
// ----------------------------------------------------------------

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("androidx.documentfile:documentfile:1.0.1")
    implementation("com.google.android.play:feature-delivery:2.1.0")
}

flutter {
    source = "../.."
}