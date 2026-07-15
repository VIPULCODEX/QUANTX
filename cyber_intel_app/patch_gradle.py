import os, sys

groovy_block = """
subprojects {
    afterEvaluate { project ->
        if (project.hasProperty("android")) {
            project.android.compileSdkVersion 36
        }
    }
}
"""

kotlin_block = """
subprojects {
    afterEvaluate {
        (extensions.findByName("android") as? com.android.build.gradle.BaseExtension)
            ?.compileSdkVersion(36)
    }
}
"""

if os.path.exists('android/build.gradle'):
    with open('android/build.gradle', 'a') as f:
        f.write(groovy_block)
    print('Patched android/build.gradle (Groovy)')
elif os.path.exists('android/build.gradle.kts'):
    with open('android/build.gradle.kts', 'a') as f:
        f.write(kotlin_block)
    print('Patched android/build.gradle.kts (Kotlin DSL)')
else:
    print('No root build file found - skipping patch')
