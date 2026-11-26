// The imperative shell: HTTP, JSON, PostgreSQL and configuration around the domain.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    application
}

kotlin {
    jvmToolchain(25)
    compilerOptions {
        allWarningsAsErrors = true
    }
}

application {
    mainClass = "io.github.nikolaiht.forsinket.app.MainKt"
}

dependencies {
    implementation(project(":domain"))
    implementation(libs.serialization.json)

    testImplementation(testFixtures(project(":domain")))
    testImplementation(libs.kotest.runner.junit5)
    testImplementation(libs.kotest.assertions.core)
    testImplementation(libs.kotest.property)
}

// The JSON examples both this service and the Elm app are tested against.
val contractExamples = rootProject.layout.projectDirectory.dir("../contract/examples")

tasks.test {
    useJUnitPlatform()
    inputs.dir(contractExamples).withPropertyName("contractExamples")
    systemProperty("contract.examples", contractExamples.asFile.absolutePath)
}
