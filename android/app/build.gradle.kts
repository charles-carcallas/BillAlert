plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ph.edu.bisu.billalert"

    // Pinned to 36, which is also Flutter 3.44's default, rather than left as
    // `flutter.compileSdkVersion` so that a Flutter upgrade cannot move it
    // without somebody deciding to.
    //
    // It was briefly 37, because flutter_secure_storage 11 requires that. That
    // does not build: the only API 37 published to the SDK manager is the
    // preview `android-37.0`, and Gradle asks for a plain `android-37` that
    // does not exist, so there is nothing to install. The dependency is held
    // at 10.3.1 instead, which compiles against 36.
    //
    // Before raising this again, check that `android-37` (no point release) is
    // actually installable — `sdkmanager --list | grep "platforms;android-37"`.
    compileSdk = 36

    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications uses java.time for scheduled reminders,
        // which Android before 8.0 lacks. Desugaring backports it; the plugin
        // requires this even for apps that never schedule anything.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ph.edu.bisu.billalert"
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

dependencies {
    // Declared rather than trusted to arrive through local_auth. styles.xml
    // makes both window themes descend from Theme.AppCompat, which the
    // fingerprint prompt needs on Android 8.1 and below. If AppCompat were
    // not on the classpath, those themes would not exist and the APK would
    // not build.
    implementation("androidx.appcompat:appcompat:1.7.1")

    // Pairs with isCoreLibraryDesugaringEnabled above; the version is the one
    // flutter_local_notifications 22 documents.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // The plugin's README reports Flutter apps with desugaring crashing on
    // Android 12L and later, and gives these as the fix.
    implementation("androidx.window:window:1.0.0")
    implementation("androidx.window:window-java:1.0.0")
}
