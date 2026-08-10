allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Some plugins (e.g. file_picker's flutter_plugin_android_lifecycle
// dependency) compile against flutter.compileSdkVersion internally, which
// this Flutter SDK defaults to 34 — too low for that dependency's AAR
// metadata check (needs 36+). Force every plugin subproject to compile
// against 36 too. Excludes :app, which evaluationDependsOn(":app") above
// already evaluates before this block runs (and which already sets
// compileSdk = 36 directly in its own build.gradle.kts).
subprojects {
    if (project.name != "app") {
        afterEvaluate {
            extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.let {
                it.compileSdkVersion(36)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
