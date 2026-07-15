import os, sys

for fname in ['android/build.gradle', 'android/build.gradle.kts']:
    if os.path.exists(fname):
        block = (
            '\nsubprojects {\n'
            '    afterEvaluate { project ->\n'
            '        if (project.hasProperty("android")) {\n'
            '            project.android.compileSdkVersion 36\n'
            '        }\n'
            '    }\n'
            '}\n'
        )
        with open(fname, 'a') as f:
            f.write(block)
        print('Patched ' + fname + ' with compileSdk 36 override')
        sys.exit(0)

print('No root build.gradle found - skipping patch')
