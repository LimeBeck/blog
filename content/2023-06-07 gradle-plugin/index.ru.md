+++
title = "Пишем и тестируем Gradle-плагин"
slug = "gradle-plugin"
date = 2023-06-07
[taxonomies]
tags = ["kotlin", "gradle", "gradle-plugin"]
+++

# Пишем и тестируем Gradle-плагин

<!-- more -->

Итак, вы решили написать Gradle плагин для, например, генерации статической конфигурации приложения во время сборки.

(на примере проекта [BUILD TIME CONFIG](https://github.com/LimeBeck/build-time-config))

## Что хотим получить:

Описываем в `build.gradle.kts` объект с определенными полями, которые определяем по время сборки 
(статически или получая из переменных окружения, например):

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

На выходе получаем где-то в исходниках такого вида объект:

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

И далее используем его в своём приложении:

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


## Создаём проект

Создаём новый Gradle проект, прописываем зависимости в `gradle/libs.versions.toml`:

```toml
[versions] # Здесь фиксируем конкретные версии, на которые можно будет ссылаться далее
kotlin = "1.7.20"
dokka = "1.7.20"

[libraries] # Указываем библиотеки, которые будут использоваться в проекте

# version.ref - ссылка на версию указанную в блоке [versions]
kotlin-plugin = { module = "org.jetbrains.kotlin:kotlin-gradle-plugin", version.ref = "kotlin" }

[plugins] # Блок с версиями Gradle плагинов
kotlin-jvm = { id = "org.jetbrains.kotlin.jvm", version.ref = "kotlin" }
kotlin-multiplatform = { id = "org.jetbrains.kotlin.multiplatform", version.ref = "kotlin" }
dokka = { id = "org.jetbrains.dokka", version.ref = "dokka" }

# Плагин для отслеживания новых версий зависимостей
versions = { id = "com.github.ben-manes.versions", version = "0.46.0" }

# Плагин для публикации плагинов в Gradle
pluginPublish = { id = "com.gradle.plugin-publish", version = "1.2.0" }
```

Описываем `build.gradle.kts`

```kotlin
plugins {
    //Через alias подключаем плагины, описанные в gradle/libs.versions.toml
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
    jvmToolchain(8)
}

//Описываем сам плагин для публикации в Gradle Portal
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

Для публикации в Gradle Portal регистрируемся в [plugins.gradle.org](https://plugins.gradle.org/), 
получаем API Key и API Secret которые прописываем в параметрах Gradle пользователя 
(можно воспользоваться мануалом на [docs.gradle.org](https:///current/userguide/publishing_gradle_plugins.html))

Дальше необходимо создать класс с плагином. Для этого унаследуемся от `org.gradle.api.Plugin<Project>`:

`src/main/kotlin/BuildTimeConfig.kt`
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

В принципе уже всё, плагин создан, он может выполнять какую-то логику во время сборки проекта.
Но нам необходимо его как то конфигурировать, для этого напишем расширение Gradle DSL:

`src/main/kotlin/BuildTimeConfigProjectExtension.kt`
```kotlin 
package dev.limebeck

import org.gradle.api.Action
import org.gradle.api.Project
import org.gradle.api.tasks.Internal

open class BuildTimeConfigProjectExtension(
    private val project: Project
) {
    @Internal //Назначение аннотаций @Internal, @Input, @Nested и т.д. будет разъяснено позднее
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
    ) //TODO: Остальные параметры конфигурации определим позднее
}

data class Config(
    val name: String,
    val packageName: String
)
```

и применим его к проекту:

`src/main/kotlin/BuildTimeConfig.kt`
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

Но наш плагин всё еще ничего не делает, необходимо добавить задачу, которая и будет собирать нашу конфигурацию в объект,
для чего унаследуемся `DefaultTask()`:

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
                |"""".trimMargin()
            )
            config.destinationDir.mkdirs()
            File(config.destinationDir, filename).writeText(file)
        }
    }
}

fun generateKotlinFile(config: Config): String = "TODO"
```

Пропишем вызов этой задачи в плагине и добавим выходные файлы задачи в sourceSets для сборки Kotlin плагином:

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
            } // Регистрация задачи и передача в нёё аргументов из DSL

            val kotlinJvmExtension = target.extensions.findByType(KotlinJvmProjectExtension::class.java)
            val kotlinMppExtension = target.extensions.findByType(KotlinMultiplatformExtension::class.java)

            val sourceSets = kotlinJvmExtension?.sourceSets
                ?: kotlinMppExtension?.sourceSets?.filter { it.name == "commonMain" }?.takeIf { it.isNotEmpty() }
                // определим, какой из плагинов используется и чьи sourceSets брать
            if (sourceSets == null) {
                target.logger.warn("BuildTimeConfig worked only with KotlinJvm or KotlinMultiplatform plugin. " 
                    + "None of them found"
                )
            }

            sourceSets?.forEach {
                it.kotlin.srcDirs(task.map { it.destinations.values }) 
                //Добавим выходные файлы задачи в sourceSets для сборки Kotlin плагином
            }
        }
    }
}
```