+++
title = "Write and test Gradle plugin"
slug = "gradle-plugin"
date = 2023-06-07
[taxonomies]
tags = ["kotlin", "gradle", "gradle-plugin"]
+++

Writing a Gradle plugin using an example of a plugin for generating static application configuration during build time [BUILD TIME CONFIG](https://github.com/LimeBeck/build-time-config)

<!-- more -->


## What We Want to Achieve:

We describe an object with specific fields in `build.gradle.kts` that we define during the build process (either statically or by retrieving them from environment variables, for example):

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

As a result, in the source code, we obtain an object like this:

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

Then, we use it in our application:

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

## Project Creation

Create a new Gradle project and specify dependencies in `gradle/libs.versions.toml`:

```toml
[versions] # Fix specific versions here for later reference
kotlin = "1.7.20"
dokka = "1.7.20"

[libraries] # Specify libraries to be used in the project

# version.ref - reference to the version specified in [versions] block
kotlin-plugin = { module = "org.jetbrains.kotlin:kotlin-gradle-plugin", version.ref = "kotlin" }

[plugins] # Block with Gradle plugin versions
kotlin-jvm = { id = "org.jetbrains.kotlin.jvm", version.ref = "kotlin" }
kotlin-multiplatform = { id = "org.jetbrains.kotlin.multiplatform", version.ref = "kotlin" }
dokka = { id = "org.jetbrains.dokka", version.ref = "dokka" }

# Plugin for tracking new dependency versions
versions = { id = "com.github.ben-manes.versions", version = "0.46.0" }

# Plugin for publishing plugins to Gradle
pluginPublish = { id = "com.gradle.plugin-publish", version = "1.2.0" }
```

Describe `build.gradle.kts`

```kotlin
plugins {
    // Use aliases to include plugins described in gradle/libs.versions.toml
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

// Describe the plugin itself for publishing to Gradle Portal
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

To publish to Gradle Portal, register at [plugins.gradle.org](https://plugins.gradle.org/),
get API Key and API Secret, and set them in Gradle user parameters
(you can use the guide on [docs.gradle.org](https://docs.gradle.org/current/userguide/publishing_gradle_plugins.html))

### Publishing to a Private Maven Repository

To publish to an internal Nexus repository, you need to describe the publication and repository in `build.gradle.kts`:

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

### Creating the Plugin Class and Gradle DSL Extension

Next, you need to create a class with the plugin. To do this, inherit from `org.gradle.api.Plugin<Project>`:

```kotlin
package dev.limebeck

import org.gradle.api.Plugin
import org.gradle.api.Project
import org.jetbrains.kotlin.gradle.dsl.KotlinJvmProjectExtension
import org.jetbrains.kotlin.gradle.dsl.KotlinMultiplatformExtension

class BuildTimeConfig : Plugin<Project> {
    override fun apply(target: Project) {
        //TODO
    }
}
```

Essentially, everything is set up now. The plugin is created, and it can perform some logic during the project build. However, we need to configure it somehow. To do this, let's write a Gradle DSL extension:

```kotlin 
package dev.limebeck

import org.gradle.api.Action
import org.gradle.api.Project
import org.gradle.api.tasks.Internal

open class BuildTimeConfigProjectExtension(
    private val project: Project
) {
    @Internal //Annotations like @Internal, @Input, @Nested, etc., will be explained later
    val configs: MutableList<Config> = mutableListOf()

    @Suppress("UNUSED")
    fun config(name: String? = null, action: Action<ConfigBuilder>) {
        val builder = ConfigBuilder(name, project.objects)
        action.execute(builder)
        configs.add(builder.build())
    }
}

open class ConfigBuilder(
    @Input
    val name: String? = null,
    private val objectFactory: ObjectFactory
) {
    @Input
    val packageName: Property<String> = objectFactory.property(String::class.java)

    fun build(): Config = Config(
        name = name ?: "unnamed", 
        packageName = packageName.get()
    ) //TODO: We'll define the remaining configuration parameters later
}

data class Config(
    val name: String,
    val packageName: String
)
```

And apply it to the project:

```kotlin
class BuildTimeConfig : Plugin<Project> {
    override fun apply(target: Project) {
        val extension = target.extensions.create(
            /* name = */ "buildTimeConfig",
            /* type = */ BuildTimeConfigProjectExtension::class.java,
            /* ...constructionArguments = */ target
        )
    }
}
```

But our plugin still doesn't do anything. We need to add a task that will collect our configuration into an object. For this, we'll inherit from `DefaultTask()`:

`BuildTimeConfigTask.kt`
```kotlin
package dev.limebeck

import org.gradle.api.DefaultTask
import org.gradle.api.tasks.Nested
import org.gradle.api.tasks.OutputDirectories
import org.gradle.api.tasks.TaskAction
import java.io.File

abstract class BuildTimeConfigTask : DefaultTask() {
    @Suppress("unused")
    @get:OutputDirectories
    val destinations: Map<String, File>
        get() = configs.associate { it.configName to it.destinationDir }

    @get:Nested
    lateinit var configs: List<Config>

    @Suppress("unused")
    @TaskAction
    fun run() {
        configs.forEach { config ->
            val file = generateKotlinFile(config)
            val filename = config.objectName + ".kt"
            logger.debug(
                """
                |Configuration: $config
                |Generated file: 
                |$file
                |""".trimMargin()
            )
            config.destinationDir.mkdirs()
            File(config.destinationDir, filename).writeText(file)
        }
    }
}

fun generateKotlinFile(config: Config): String = "TODO"
```

Let's register this task in the plugin and add the task's output files to the sourceSets for Kotlin plugin builds:

`src/main/kotlin/BuildTimeConfig.kt`
```kotlin
class BuildTimeConfig : Plugin<Project> {
    override fun apply(target: Project) {
        val extension = target.extensions.create(
            /* name = */ "buildTimeConfig",
            /* type = */ BuildTimeConfigProjectExtension::class.java,
            /* ...constructionArguments = */ target
        )

        target.afterEvaluate {
            val task = target.tasks.register("generateConfig", BuildTimeConfigTask::class.java) {
                it.configs = extension.configs
            } // Registering the task and passing arguments from DSL to it

            val kotlinJvmExtension = target.extensions.findByType(KotlinJvmProjectExtension::class.java)
            val kotlinMppExtension = target.extensions.findByType(KotlinMultiplatformExtension::class.java)

            val sourceSets = kotlinJvmExtension?.sourceSets
                ?: kotlinMppExtension?.sourceSets?.filter { it.name == "commonMain" }?.takeIf { it.isNotEmpty() }
                // Determine which plugin is used and whose sourceSets to take
            if (sourceSets == null) {
                target.logger.warn("BuildTimeConfig worked only with KotlinJvm or KotlinMultiplatform plugin. " 
                    + "None of them found"
                )
            }

            sourceSets?.forEach {
                it.kotlin.srcDirs(task.map { it.destinations.values }) 
                // Add the task's output files to sourceSets for Kotlin plugin builds
            }
        }
    }
}
```

### Incremental Build

Incremental build is actively promoted in newer versions of Gradle - to avoid unnecessary tasks execution when there are no changes in the input data.

For this, all data operated by the plugin (especially extension and task) must be explicitly defined as:
* Input - input
* Output - result
* Internal - intermediate data that does not affect the result

More details are outlined in the Gradle documentation in the [Incremental build](https://docs.gradle.org/current/userguide/incremental_build.html) section.

## Adding Functionality

Now we have a plugin with a task. The file generation logic is beyond the scope of this article, so let's provide the full listing:


`src/main/kotlin/ConfigBuilder.kt`
```kotlin
package dev.limebeck

import org.gradle.api.Action
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.model.ObjectFactory
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.OutputDirectory
import java.io.File
import kotlin.reflect.KClass

open class ConfigBuilder(
    @Input
    val name: String? = null,
    private val objectFactory: ObjectFactory
) {

    @Input
    val packageName: Property<String> = objectFactory.property(String::class.java)

    @Input
    val objectName: Property<String> = objectFactory.property(String::class.java)

    @OutputDirectory
    val destination: RegularFileProperty = objectFactory.fileProperty()

    @Input
    val allProperties: MutableList<ConfigPropertyHolder> = mutableListOf()

    internal fun build(): Config {
        val name = name ?: "unnamed"
        return Config(
            configName = name,
            packageName = packageName.get(),
            objectName = objectName.get(),
            properties = allProperties,
            destinationDir = File(destination.get().asFile, name)
        )
    }

    @Suppress("UNUSED")
    fun configProperties(action: Action<ConfigPropertiesBuilder>) {
        val builder = ConfigPropertiesBuilder()
        action.execute(builder)
        allProperties.addAll(builder.allConfigProperties)
    }
}

open class ConfigPropertiesBuilder {
    val allConfigProperties: MutableList<ConfigPropertyHolder> = mutableListOf()

    fun <T : Any> property(name: String, type: KClass<T>): ConfigPropertyDefinition<T> {
        return ConfigPropertyDefinition(name, type)
    }

    @Suppress("UNUSED")
    inline fun <reified T : Any> property(name: String) = property(name, T::class)

    infix fun <T : Any> ConfigPropertyDefinition<T>.set(value: T?) {
        allConfigProperties.add(
            ConfigProperty(
                name = name,
                type = type,
                value = value
            )
        )
    }

    @Suppress("UNUSED")
    fun obj(name: String) = ConfigObjectDefinition(name)

    infix fun ConfigObjectDefinition.set(action: Action<ConfigPropertiesBuilder>) {
        val builder = ConfigPropertiesBuilder()
        action.execute(builder)
        allConfigProperties.add(ConfigObject(name, builder.allConfigProperties))
    }

    data class ConfigPropertyDefinition<T : Any>(
        val name: String,
        val type: KClass<T>
    )

    data class ConfigObjectDefinition(
        val name: String
    )
}
```

`src/main/kotlin/ConfigModels.kt`
```kotlin
package dev.limebeck

import org.gradle.api.tasks.Input
import org.gradle.api.tasks.Internal
import org.gradle.api.tasks.Nested
import org.gradle.api.tasks.OutputDirectory
import java.io.File
import kotlin.reflect.KClass

data class Config(
    @Input
    val configName: String,
    @Input
    val packageName: String,
    @Input
    val objectName: String,
    @Nested
    val properties: List<ConfigPropertyHolder>,
    @OutputDirectory
    val destinationDir: File
)

sealed class ConfigPropertyHolder(
    @Input open val name: String
)

data class ConfigProperty<T : Any>(
    @Input
    override val name: String,
    @Internal
    val type: KClass<T>,
    @Input
    val value: T?
) : ConfigPropertyHolder(name)

data class ConfigObject(
    @Input
    override val name: String,
    @Nested
    val properties: List<ConfigPropertyHolder>,
) : ConfigPropertyHolder(name)
```

Add code generation dependency in `build.gradle.kts`:
```kotlin
dependencies {
    implementation(libs.kotlinpoet)
}
```

We'll replace the code generation function with the following:

`src/main/kotlin/ConfigWriter.kt`
```kotlin
package dev.limebeck

import com.squareup.kotlinpoet.FileSpec
import com.squareup.kotlinpoet.PropertySpec
import com.squareup.kotlinpoet.TypeSpec
import java.security.InvalidParameterException
import kotlin.reflect.full.isSubclassOf

fun TypeSpec.Builder.makeProperty(prop: ConfigPropertyHolder) {
    when (prop) {
        is ConfigObject -> {
            val type = TypeSpec.objectBuilder(prop.name).also { b ->
                prop.properties.forEach { b.makeProperty(it) }
            }.build()
            addType(type)
        }

        is ConfigProperty<*> -> {
            val template = when {
                prop.type.isSubclassOf(Boolean::class) -> "%L"
                prop.type.isSubclassOf(Number::class) -> "%L"
                prop.type.isSubclassOf(String::class) -> "%S"
                else -> throw InvalidParameterException("<4ac3a89c> Unknown property type ${prop.type}")
            }
            val prop = PropertySpec
                .builder(prop.name, prop.type)
                .initializer(template, prop.value)
                .build()
            addProperty(prop)
        }
    }
}

fun generateKotlinFile(config: Config): String {
    val propertyObj = TypeSpec
        .objectBuilder(config.objectName)
        .apply {
            config.properties.forEach { makeProperty(it) }
        }.build()

    val fileSpec = FileSpec
        .builder(config.packageName, config.objectName + ".kt")
        .addType(propertyObj)
        .build()

    return StringBuilder().also {
        fileSpec.writeTo(it)
    }.toString()
}
```

## Plugin Testing

### Naive Approach

* Publish the plugin to MavenLocal.
* Create a new project.
* Include the plugin from MavenLocal. To do this, add:
   ```kotlin
    pluginManagement {
        repositories {
            mavenLocal()
            gradlePortal()
            mavenCentral()
        }
    }
    ```

Pros:
* Quick to write.
* Quick to test.

Cons:
* Not possible to test automatically.

### Testing with Gradle TestKit

Let's add new dependencies required for testing:

`build.gradle.kts`
```kotlin
dependencies {
    testImplementation("org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.8.21")
    testImplementation(kotlin("test"))
    testImplementation(gradleTestKit())
}

tasks.test {
    useJUnitPlatform()
}
```

Create a test file where we simply ensure that the task executes successfully:

`src/test/kotlin/PluginTest.kt`
```kotlin
import org.gradle.testkit.runner.GradleRunner
import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Path
import kotlin.io.path.createFile
import kotlin.io.path.writeText
import kotlin.io.path.createDirectories
import kotlin.test.assertEquals

class PluginTest {

    @TempDir
    lateinit var testProjectDir: Path

    private lateinit var gradleRunner: GradleRunner

    @BeforeEach
    fun setup() {
        gradleRunner = GradleRunner.create()
            .withPluginClasspath()
            .withProjectDir(testProjectDir.toFile())
            .withTestKitDir(testProjectDir.resolve("./testKit").createDirectories().toFile())
    }

    @Test
    fun `Generate build time config`() {
        val buildGradleContent = """
            plugins {
                kotlin("jvm") version "1.8.0"
                id("dev.limebeck.build-time-config")
            }
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
        """.trimIndent()
        testProjectDir
            .resolve("build.gradle.kts")
            .createFile()
            .writeText(buildGradleContent)
        testProjectDir
            .resolve("settings.gradle.kts")
            .createFile()
            .writeText("rootProject.name = \"build-time-config-test\"")

        val codeGenerationResult = gradleRunner.withArguments("generateConfig").build()
        assertEquals(TaskOutcome.SUCCESS, codeGenerationResult.task(":generateConfig")!!.outcome)
    }
}
```