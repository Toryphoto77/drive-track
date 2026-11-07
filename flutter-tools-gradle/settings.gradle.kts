pluginManagement {
    repositories {
        maven { url = uri("file:///home/hatch/gradle-offline-mirror") }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        maven { url = uri("file:///home/hatch/gradle-offline-mirror") }
        google()
        mavenCentral()
    }
}
