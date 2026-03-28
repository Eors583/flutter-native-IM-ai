import java.io.File
import java.net.URI

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val downloadMnnNativeLibs by tasks.registering {
    val outDir = layout.projectDirectory.dir("src/main/jniLibs/arm64-v8a").asFile
    val marker = File(outDir, ".mnn_3.4.1_ok")
    outputs.file(marker)
    doLast {
        if (marker.exists() || File(outDir, "libMNN.so").exists()) {
            if (!marker.exists()) marker.writeText("ok")
            return@doLast
        }
        outDir.mkdirs()
        val zipFile = File(temporaryDir, "mnn_android.zip")
        URI(
            "https://github.com/alibaba/MNN/releases/download/3.4.1/mnn_3.4.1_android_armv7_armv8_cpu_opencl_vulkan.zip",
        ).toURL().openStream().use { input ->
            zipFile.outputStream().use { input.copyTo(it) }
        }
        val unzipRoot = File(temporaryDir, "mnn_unzipped")
        unzipRoot.deleteRecursively()
        copy {
            from(zipTree(zipFile))
            into(unzipRoot)
        }
        val arm64 =
            unzipRoot.walkTopDown().firstOrNull { it.isDirectory && it.name == "arm64-v8a" }
                ?: error("arm64-v8a not found in MNN zip")
        arm64.listFiles()?.forEach { f ->
            if (f.isFile && f.extension == "so") {
                f.copyTo(File(outDir, f.name), overwrite = true)
            }
        }
        marker.writeText("ok")
    }
}

android {
    namespace = "com.aiim.flutter_native_im_ai"
    compileSdk = flutter.compileSdkVersion
    // 统一 NDK 版本，避免插件要求更高版本导致构建告警
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.aiim.flutter_native_im_ai"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
        val repoRoot = file("${project.projectDir}/../..").absolutePath.replace('\\', '/')
        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
                arguments += listOf(
                    "-DANDROID_STL=c++_shared",
                    "-DAIIM_REPO_ROOT=$repoRoot",
                )
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

tasks.named("preBuild") {
    dependsOn(downloadMnnNativeLibs)
}

flutter {
    source = "../.."
}
