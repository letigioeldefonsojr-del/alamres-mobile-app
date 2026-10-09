plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.capstone_application_development"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (the "Shop Reminders"
        // feature) - without this the build fails with a desugaring error.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.capstone_application_development"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            // Was true, with proguardFiles pointing at proguard-rules.pro -
            // turned off entirely rather than chasing exact keep rules.
            // R8 (the code shrinker this enables) was silently stripping
            // internal classes that Firebase Auth / Google Sign-In need to
            // persist and restore a signed-in session, which is what broke
            // "Keep me logged in" in every release APK build (flutter build
            // apk defaults to this release build type) while a plain debug
            // `flutter run` - which never minifies - worked fine. A
            // targeted keep-rules file (still in proguard-rules.pro) is the
            // "right" fix for a production app, but for this project a
            // somewhat larger APK is a trivial cost next to actually having
            // a working app - so shrinking is just off.
            isMinifyEnabled = false
            // Flutter's own Gradle plugin defaults release builds to
            // shrinking resources, which Android Gradle Plugin refuses to
            // do with isMinifyEnabled off ("Removing unused resources
            // requires unused code shrinking to be turned on"). Override
            // that default explicitly rather than re-enabling minification
            // just to satisfy it.
            isShrinkResources = false
        }
    }
}

configurations.all {
    resolutionStrategy {
        force("androidx.work:work-runtime:2.10.0")
        force("androidx.work:work-runtime-ktx:2.10.0")
    }
}

dependencies {
    // Required by flutter_local_notifications alongside isCoreLibraryDesugaringEnabled above.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}