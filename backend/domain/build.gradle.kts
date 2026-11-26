// The functional core. It may depend on the Kotlin standard library and
// arrow-core, and on nothing that does I/O: no Ktor, no JDBC, no serialization.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.ktlint)
    `java-test-fixtures`
}

kotlin {
    jvmToolchain(25)
    compilerOptions {
        allWarningsAsErrors = true
    }
}

ktlint {
    version = libs.versions.ktlint
}

dependencies {
    api(libs.arrow.core)

    testFixturesApi(libs.kotest.property)

    testImplementation(libs.kotest.runner.junit5)
    testImplementation(libs.kotest.assertions.core)
    testImplementation(libs.kotest.property)
}

tasks.test {
    useJUnitPlatform()
}
