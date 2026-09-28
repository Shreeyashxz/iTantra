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

subprojects {
    if (project.name.startsWith("sherpa_onnx_android")) {
        tasks.matching { it.name.contains("JniLib", ignoreCase = true) || it.name.contains("NativeLib", ignoreCase = true) }.configureEach {
            doLast {
                val buildDir = layout.buildDirectory.asFile.get()
                if (buildDir.exists()) {
                    buildDir.walkTopDown().filter { it.name == "libonnxruntime.so" }.forEach { file ->
                        file.delete()
                        println("[Gradle] Excluded sherpa libonnxruntime.so from: ${file.absolutePath}")
                    }
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
