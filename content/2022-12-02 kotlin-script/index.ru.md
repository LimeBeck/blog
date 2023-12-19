+++
title = "Используем Kotlin Script для конфигурации через DSL (IN-PROGRESS)"
slug = "kotlin-script"
date = 2023-12-10
[taxonomies]
tags = ["kotlin"]
+++

Если вы знакомы с Gradle, то скорее всего, вам уже доводилось сталкиваться с конфигурацией через Kotlin Script (\*.kts) и вы оценили удобство Kotlin и возможности не только подсветки синтаксиса, но и интеллектуального дополнения, основанного на строгой типизации. Поговорим о том, как это работает и как в своём приложении реализовать конфигурацию через DSL с помощью Kotlin Script и как использовать Kotlin Script вместо bash и python скриптов при автоматизации своих задач.

{{danger(text = "DISCLAIMER")}}: На момент написания статьи Kotlin Script всё еще находится в альфа-версии и его API довольно неинтуитивно, нестабильно и не рекомендуется к использованию в критичных местах

<!-- more -->

План:
1. Введение в Kotlin Script на примере Gradle kts
1. KEEP Scripting Support
1. Kotlin Script как способ описания логики в приложениях
    1. Script definition
    1. Script loader
    1. Подсветка синтаксиса в IDE
        1. Собственный плагин для поддержки верного контекста скрипта без Gradle проекта
    1. Собираем всё вместе
    1. Безопасность (ограничение доступного classpath)
1. Kotlin Script как замена bash-скриптам
    1. `main.kts`
1. Недостатки Kotlin Script
1. Примеры использования

# Введение

Для начала, давайте посмотрим, как позиционируют Kotlin скриптинг сами Jetbrains:

* Applications
    * Build scripts (Gradle/Kobalt)
    * Test scripts (Spek)
    * Command-line utilities
    * Routing scripts (ktor)
    * Type-safe configuration files (TeamCity)
    * In-process scripting and REPL for IDE
    * Consoles like IPython/Jupyter Notebook
    * Game scripting engines
    * ...

Т.е. применения, грубо говоря, можно поделить на три категории:
* REPL (в т.ч. им можно считать Jupyter Notebook)
* Встраивание скриптового движка в приложение
* Замена тех же BASH-скриптов в автоматизации задач
* Скрипты, которые компилируются вместе с исходниками (те же тесты со Spek)

Но работают они на самом деле все по одному принципу, отличается только точка вызова

# Kotlin Script как способ описания логики в приложениях

Когда я только начинал разбираться с Gradle, мне никак не давалась концепция его конфигурации, и только когда я наконец осознал, что `build.gradle.kts` - это не скрипт сборки (подобный `ant`-скриптам), а скрипт конфигурации сборки, я смог уложить всё в голове.

То есть всё, что мы делаем в `build.gradle.kts` - лишь используем DSL для постоения объекта конфигурации сборки.
Мы даже можем посмотреть, в каком контексте находится наш код:

![](img/gradle_this.png)

Посмотрим, как можно сделать так же в своём приложение и использовать всю мощь Kotlin DSL на примере обертки для RevealJs

## Основные компоненты инфраструктуры запуска скрипта

### Script Definition

Для начала, нам нужно описать, с каким расширением будет наш скрипт и будет определяться его компиляция и рантайм:

`scriptDef.kt`
```kotlin
@KotlinScript(
    fileExtension = "reveal.kts",
    compilationConfiguration = RevealKtScriptCompilationConfiguration::class,
    evaluationConfiguration = RevealKtEvaluationConfiguration::class,
)
abstract class RevealKtScript //Класс обязательно должен быть открытым или абстрактным
```

```kotlin
object RevealKtScriptCompilationConfiguration : ScriptCompilationConfiguration({
    jvm {
        dependenciesFromCurrentContext(wholeClasspath = true)
    }
    defaultImports(DependsOn::class, Repository::class)
    defaultImports(
        "dev.limebeck.revealkt.core.elements.*",
        "dev.limebeck.revealkt.dsl.*",
        "dev.limebeck.revealkt.dsl.slides.*"
    )
    implicitReceivers(RevealKtBuilder::class)
    ide {
        acceptedLocations(ScriptAcceptedLocation.Everywhere)
    }
    
    //Костыль, без которого скриптинг не работает после версии 1.7.20
    compilerOptions.append("-Xadd-modules=ALL-MODULE-PATH") 
})
```

Если есть желание добавить возможность в скрипте подключать любые зависимости из Maven-репозиториев, 
то можно добавить в конфигурацию компиляции следующее:

(внутри `RevealKtScriptCompilationConfiguration`)
```kotlin
    refineConfiguration {
        // Process specified annotations with the provided handler
        onAnnotations(DependsOn::class, Repository::class, handler = ::configureMavenDepsOnAnnotations)
    }

    // Handler that reconfigures the compilation on the fly
    fun configureMavenDepsOnAnnotations(
        context: ScriptConfigurationRefinementContext
    ): ResultWithDiagnostics<ScriptCompilationConfiguration> {
        val annotations = context.collectedData?.get(ScriptCollectedData.collectedAnnotations)
            ?.takeIf { it.isNotEmpty() }
            ?: return context.compilationConfiguration.asSuccess()
        return runBlocking {
            resolver.resolveFromScriptSourceAnnotations(annotations)
        }.onSuccess {
            context.compilationConfiguration.with {
                dependencies.append(JvmDependency(it))
            }.asSuccess()
        }
    }

    private val resolver = CompoundDependenciesResolver(
        FileSystemDependenciesResolver(), 
        MavenDependenciesResolver()
    )
```

Для того, чтобы IDEA распознала наши скрипты `My-Shiny-Presentation.revealkt.kts` необходимо добавить в 
`META-INF/kotlin/script/templates` проекта пустой файл с full qualified name в названии:

`META-INF/kotlin/script/templates/dev.limebeck.revealkt.scripts.RevealKtScript.classname`

### Script Loader

В принципе, всё, что необходимо для выполнения нашего скрипта - вот эти строчки:

```kotlin
fun BasicJvmScriptingHost.evalFile(scriptFile: File): ResultWithDiagnostics<EvaluationResult> {
    val compilationConfiguration = createJvmCompilationConfigurationFromTemplate<RevealKtScript> { 
        //Тут мы можем дополнить и переопределить конфигурацию при необходимости
    }
    val evaluationConfiguration = createJvmEvaluationConfigurationFromTemplate<RevealKtScript> {
        //Тут мы можем дополнить и переопределить конфигурацию при необходимости
    }
    return eval(
        script = scriptFile.toScriptSource(),
        compilationConfiguration = compilationConfiguration,
        evaluationConfiguration = evaluationConfiguration
    )
}

val scriptingHost = BasicJvmScriptingHost()
val result = scriptingHost.evalFile(scriptFile)
```

Получить наш билдер после выполнения можно следующим образом:

```kotlin
val implicitReceivers = result.valueOrNull()
    ?.configuration
    ?.notTransientData
    ?.entries
    ?.find { it.key.name == "implicitReceivers" }?.value as? List<*>

val builder = implicitReceivers?.filterIsInstance<RevealKtBuilder>()?.firstOrNull()
```

## Подсветка в IDE

Для работы подсветки в IDE необходимо, чтобы в classpath текущего проекта находилась наша библиотека с script definition

# Недостатки

* Не хватает возможности в самом скрипте определить артефакт и репозиторий с Script Definition
* Подсветка кода работает только в IDEA
* Общая сырость
* Время выполнения (первый запуск до нескольких секунд)

# Заметки

## Примеры проектов с использованием Kotlin Script

* https://github.com/dkandalov/live-plugin
* https://github.com/typesafegithub/github-workflows-kt
* https://github.com/formatools/forma
* https://github.com/LimeBeck/reveal-kt

## Ссылки

* https://github.com/Kotlin/KEEP/blob/master/proposals/scripting-support.md#implementation-status
* https://github.com/Kotlin/KEEP/issues/75