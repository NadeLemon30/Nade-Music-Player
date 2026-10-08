plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.nade.musicplayer"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.nade.musicplayer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Produce a human-named copy of every assembled APK: "Nade's Music Player.apk".
// Flutter's Gradle plugin always publishes its artifact as
// build/app/outputs/flutter-apk/app-<mode>.apk, and `flutter build apk`
// validates that exact name after the build (and `flutter run`/install lookup
// the same name), so the branded file is an extra copy made once the assemble
// task — including Flutter's own copy step — has finished.
val brandedApkName = "Nade's Music Player.apk"
val brandedApkDirectory = layout.buildDirectory.dir("outputs/flutter-apk")

listOf("Debug", "Profile", "Release").forEach { variantName ->
    val buildMode = variantName.replaceFirstChar { it.lowercaseChar() }
    val copyBrandedApk = tasks.register("copyBrandedApk$variantName") {
        val sourceApk = brandedApkDirectory.map { it.file("app-$buildMode.apk") }
        val targetApk = brandedApkDirectory.map { it.file(brandedApkName) }
        doLast {
            val sourceFile = sourceApk.get().asFile
            if (sourceFile.isFile) {
                sourceFile.copyTo(targetApk.get().asFile, overwrite = true)
            }
        }
    }
    tasks.matching { it.name == "assemble$variantName" }.configureEach {
        finalizedBy(copyBrandedApk)
    }
}
