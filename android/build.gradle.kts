import java.util.Properties

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

group = "com.stage3d.stage_3d"
version = "1.0"

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { stream -> localProperties.load(stream) }
}
val flutterSdkPath = localProperties.getProperty("flutter.sdk") ?: System.getenv("FLUTTER_ROOT")

repositories {
    google()
    mavenCentral()
}

android {
    namespace = "com.stage3d.stage_3d"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 23

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
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

val filamentVersion = "1.71.5"
val filamentMaterialsDir = file("src/main/assets/materials")
val hostOs = System.getProperty("os.name").lowercase()
val hostArch = System.getProperty("os.arch").lowercase()
val matcClassifier =
    when {
        hostOs.contains("windows") -> "windows-x86_64"
        hostOs.contains("linux") -> "linux-x86_64"
        hostOs.contains("mac") && (hostArch.contains("aarch64") || hostArch.contains("arm64")) ->
            "osx-aarch_64"
        else ->
            error(
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

    inputs.files(fileTree(filamentMaterialsDir) { include("*.mat", "*.shader") })
    inputs.files(filamentMatc)
    outputs.dir(filamentMaterialsDir)

    onlyIf { filamentMaterialsDir.exists() }

    doLast {
        val matc = filamentMatc.singleFile
        matc.setExecutable(true)
        val sources =
            filamentMaterialsDir
                .listFiles { file -> file.extension == "mat" || file.extension == "shader" }
                .orEmpty()
                .groupBy { it.nameWithoutExtension }
                .values
                .map { files -> files.firstOrNull { it.extension == "mat" } ?: files.first() }
        sources.forEach { source ->
            val output = source.resolveSibling("${source.nameWithoutExtension}.filamat")
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
    if (flutterSdkPath != null) {
        compileOnly(files("$flutterSdkPath/bin/cache/artifacts/engine/android-arm64/flutter.jar"))
    }
    add("filamentMatc", "com.google.android.filament:matc:$filamentVersion:$matcClassifier@exe")
    implementation("com.google.android.filament:filament-android:$filamentVersion")
    implementation("com.google.android.filament:gltfio-android:$filamentVersion")
    implementation("com.google.android.filament:filament-utils-android:$filamentVersion")
}
