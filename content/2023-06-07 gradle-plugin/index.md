+++
title = "Write and test Gradle plugin"
slug = "gradle-plugin"
date = 2023-06-07
[taxonomies]
tags = ["kotlin", "gradle", "gradle-plugin"]
+++

Writing and testing a Gradle plugin, using the example of a build-time application config generation plugin ([BUILD TIME CONFIG](https://github.com/LimeBeck/build-time-config))

<!-- more -->

## What we want

We describe an object with certain fields (hardcode them or retrieve from environment variables, whatever)

`build.gradle.kts`
```kotlin 
plugins {
    kotlin("jvm") version "1.8.0"
    id("dev.limebeck.build-time-config") version "1.1.2"
}
...
buildTimeConfig {
    config {
        packageName.set("dev.limebeck.config")
        objectName.set("MyConfig")
        destination.set(project.buildDir)

        configProperties {
            property<String>("someProp") set "SomeValue"
            property<Int>("someProp2") set 123
            property<Double>("someProp3") set 123.0
            property<Long>("someProp4") set 123L
            property<Boolean>("someProp5") set true
            obj("nested") set {
                property<String>("someProp") set "SomeValue"
            }
        }
    }
}
```

To get somewhere in sources file with object like this:

```kotlin
package dev.limebeck.config

import kotlin.Boolean
import kotlin.Double
import kotlin.Int
import kotlin.Long
import kotlin.String

public object MyConfig {
    public val someProp: String = "SomeValue"

    public val someProp2: Int = 123

    public val someProp3: Double = 123.0

    public val someProp4: Long = 123

    public val someProp5: Boolean = true

    public object nested {
        public val someProp: String = "SomeValue"
    }
}
```

Which we can use in application later:

`Application.kt`
```kotlin
import dev.limebeck.config.MyConfig

class Application {
    val data: String = MyConfig.someProp
    val data2: Int = MyConfig.someProp2
    val data3: Double = MyConfig.someProp3
    val data4: Long = MyConfig.someProp4
    val data5: Boolean = MyConfig.someProp5
    val obj: String = MyConfig.nested.someProp
}
```

## First step: project creation

Create a new Gradle project and specify dependencies in `gradle/libs.versions.toml` file:

```toml
[versions] # Common versions here
kotlin = "1.7.20"
dokka = "1.7.20"

[libraries] # Library dependencies

# version.ref - refence to version in [versions] block
kotlin-plugin = { module = "org.jetbrains.kotlin:kotlin-gradle-plugin", version.ref = "kotlin" }

[plugins] # Gradle plugins versions

# Kotlin plugins, that we extend later
kotlin-jvm = { id = "org.jetbrains.kotlin.jvm", version.ref = "kotlin" }
kotlin-multiplatform = { id = "org.jetbrains.kotlin.multiplatform", version.ref = "kotlin" }
dokka = { id = "org.jetbrains.dokka", version.ref = "dokka" }

# Gradle plugin for publishing to gradle plugin portal
pluginPublish = { id = "com.gradle.plugin-publish", version = "1.2.0" }
```

Create `build.gradle.kts`:
```kotlin
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.pluginPublish)
    alias(libs.plugins.versions)
    `java-gradle-plugin`
    `maven-publish`
}

group = "dev.limebeck"
version = "1.0.0"

repositories {
    mavenCentral()
}

dependencies {
    compileOnly(gradleApi())
    implementation(libs.kotlin.plugin)
}

kotlin {
    jvmToolchain(17)
}

//Configure publishing to Gradle Portal
gradlePlugin {
    website.set("https://github.com/LimeBeck/BuildTimeConfig")
    vcsUrl.set("https://github.com/LimeBeck/BuildTimeConfig.git")
    plugins {
        create("buildTimeConfig") {
            id = "dev.limebeck.build-time-config"
            displayName = "Kotlin Build-Time Config"
            description = "Gradle plugin for providing build-time configuration properties for kotlin application"
            tags.set(listOf("kotlin", "config"))
            implementationClass = "dev.limebeck.BuildTimeConfig"
        }
    }
}
```

For publishin to Gradle plugin portal we need to:
1. Create an account on [plugins.gradle.org](https://plugins.gradle.org/user/register)
1. Create an API key
1. Add your API key to your Gradle configuration

This can be done by manual on [docs.gradle.org](https://docs.gradle.org/current/userguide/publishing_gradle_plugins.html)

### Publish our plugin to private Maven repository (Nexus etc)

We need to add publications and repository sections in our `build.gradle.kts`:

```kotlin
publishing {
    repositories {
        maven {
            name = "InternalRepo"
            url = uri(
                System.getenv("PUBLISH_REPO_URI")
                    ?: project.findProperty("publish.repo.uri") as String
            )
            isAllowInsecureProtocol = true
 
            val username = System.getenv("PUBLISH_REPO_USERNAME")
                ?: project.findProperty("publish.repo.username") as String?
            val password = System.getenv("PUBLISH_REPO_PASSWORD")
                ?: project.findProperty("publish.repo.password") as String?
            if (username != null && password != null) {
                credentials {
                    this.username = username
                    this.password = password
                }
            }
        }
    }
    publications {
        create<MavenPublication>("build-time-config-plugin") {
            from(components["java"])
            groupId = "dev.limebeck"
            artifactId = "build-time-config-plugin"
            pom {
                name.set("Kotlin Build-Time Config")
                description.set("Gradle plugin for providing build-time configuration properties for kotlin application")
                groupId = "dev.limebeck"
            }
        }
    }
}
```

## Plugin

Let`s start 