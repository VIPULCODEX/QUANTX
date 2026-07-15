import os, sys

groovy_block = """
subprojects {
    afterEvaluate { project ->
        if (project.hasProperty("android")) {
            project.android.compileSdkVersion 34
        }
    }
}
"""

kotlin_block = """
subprojects {
    afterEvaluate {
        if (extensions.findByName("android") != null) {
            extensions.configure<com.android.build.gradle.BaseExtension>("android") {
                compileSdkVersion(34)
            }
        }
    }
}
"""

if os.path.exists('android/build.gradle'):
    with open('android/build.gradle', 'a') as f:
        f.write(groovy_block)
    print('Patched android/build.gradle (Groovy) with compileSdk 34')
elif os.path.exists('android/build.gradle.kts'):
    with open('android/build.gradle.kts', 'a') as f:
        f.write(kotlin_block)
    print('Patched android/build.gradle.kts (Kotlin DSL) with compileSdk 34')
else:
    print('No root build file found - skipping patch')
