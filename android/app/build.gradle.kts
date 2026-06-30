plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

repositories {
    google()
    mavenCentral()
}

layout.buildDirectory.set(rootProject.layout.projectDirectory.dir("../build/app"))

android {
    namespace = "com.example.jolt_physics_dart"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.jolt_physics_dart"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
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

val filamentVersion = "1.71.5"
val filamentMaterialSourcesDir = file("../../assets/material_sources")
val filamentMaterialsDir = file("src/main/assets/materials")
val hostOs = System.getProperty("os.name").lowercase()
val hostArch = System.getProperty("os.arch").lowercase()
val matcClassifier = when {
    hostOs.contains("windows") -> "windows-x86_64"
    hostOs.contains("linux") -> "linux-x86_64"
    hostOs.contains("mac") && (hostArch.contains("aarch64") || hostArch.contains("arm64")) ->
        "osx-aarch_64"
    else -> error(
        "Unsupported Filament matc host: os=${System.getProperty("os.name")}, " +
            "arch=${System.getProperty("os.arch")}. Filament $filamentVersion publishes " +
            "matc for windows-x86_64, linux-x86_64, and osx-aarch_64.",
    )
}
val filamentMatc by configurations.creating {
    isCanBeConsumed = false
    isCanBeResolved = true
}

val compileFilamentMaterials by tasks.registering {
    group = "filament"
    description = "Compiles Filament .mat material sources into .filamat Android assets."

    inputs.files(fileTree(filamentMaterialSourcesDir) { include("*.mat", "*.shader") })
    inputs.files(filamentMatc)
    outputs.dir(filamentMaterialsDir)

    onlyIf { filamentMaterialSourcesDir.exists() }

    doLast {
        val matc = filamentMatc.singleFile
        matc.setExecutable(true)
        filamentMaterialsDir.mkdirs()
        val sources = filamentMaterialSourcesDir
            .listFiles { file -> file.extension == "mat" || file.extension == "shader" }
            .orEmpty()
            .groupBy { it.nameWithoutExtension }
            .values
            .map { files -> files.firstOrNull { it.extension == "mat" } ?: files.first() }
        sources.forEach { source ->
                val output = filamentMaterialsDir.resolve("${source.nameWithoutExtension}.filamat")
                providers.exec {
                    commandLine(
                        matc.absolutePath,
                        "-p",
                        "mobile",
                        "-a",
                        "opengl",
                        "-o",
                        output.absolutePath,
                        source.absolutePath,
                    )
                }.result.get()
        }
    }
}

tasks.configureEach {
    if (name.startsWith("merge") && name.endsWith("Assets")) {
        dependsOn(compileFilamentMaterials)
    }
}

dependencies {
    add("filamentMatc", "com.google.android.filament:matc:$filamentVersion:$matcClassifier@exe")
    implementation("com.google.android.filament:filament-android:$filamentVersion")
    implementation("com.google.android.filament:gltfio-android:$filamentVersion")
    implementation("com.google.android.filament:filament-utils-android:$filamentVersion")
}
