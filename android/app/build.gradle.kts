plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

/**
 * The sessions screen is the web app itself, run from the APK's assets so it works with no
 * network. It is copied in at build time rather than committed a second time, so the page in the
 * app can never drift from the one GitHub Pages serves.
 */
val webAppAssets = layout.buildDirectory.dir("generated/webapp").get().asFile

val copyWebApp by tasks.registering(Copy::class) {
    from(rootProject.projectDir.parentFile) {
        include("index.html", "manifest.webmanifest", "icon-*.png")
    }
    into(webAppAssets)
}

android {
    namespace = "com.marketsessions.widget"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.marketsessions.widget"
        minSdk = 26
        targetSdk = 34
        versionCode = 6
        versionName = "1.5"
    }

    sourceSets["main"].assets.srcDir(webAppAssets)

    /**
     * A debug APK is signed with whatever throwaway key the build machine happens to have, and
     * Android refuses to replace an installed app whose signature differs. Signing with a stored
     * key instead means every build installs over the last one. Without the environment — a local
     * checkout, or a fork with no secret — this falls through to the usual debug key.
     */
    signingConfigs {
        getByName("debug") {
            val keystorePath = System.getenv("SIGNING_KEYSTORE_FILE")
            if (!keystorePath.isNullOrBlank() && file(keystorePath).exists()) {
                storeFile = file(keystorePath)
                storePassword = System.getenv("SIGNING_KEYSTORE_PASSWORD")
                keyAlias = "market-sessions"
                keyPassword = System.getenv("SIGNING_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

tasks.named("preBuild") { dependsOn(copyWebApp) }
