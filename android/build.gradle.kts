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

// Some plugins (e.g. file_picker) still compile against Android 34, but the
// libraries they pull in need 36. Raise every plugin to 36 so the build passes.
subprojects {
    val raise: Project.() -> Unit = {
        if (plugins.hasPlugin("com.android.library")) {
            extensions.getByName("android").withGroovyBuilder { "compileSdkVersion"(36) }
        }
    }
    if (state.executed) raise() else afterEvaluate { raise() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
