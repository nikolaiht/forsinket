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
    // Netty loads a native library for its transport, which newer JDKs want declared.
    applicationDefaultJvmArgs = listOf("--enable-native-access=ALL-UNNAMED")
}

dependencies {
    implementation(project(":domain"))
    implementation(libs.serialization.json)
    implementation(platform(libs.ktor.bom))
    implementation(libs.ktor.server.core)
    implementation(libs.ktor.server.netty)
    implementation(libs.ktor.server.content.negotiation)
    implementation(libs.ktor.server.status.pages)
    implementation(libs.ktor.serialization.kotlinx.json)
    implementation(libs.hikari)
    implementation(libs.flyway.core)
    runtimeOnly(libs.flyway.postgresql)
    runtimeOnly(libs.postgresql)
    runtimeOnly(libs.logback)

    testImplementation(testFixtures(project(":domain")))
    testImplementation(libs.kotest.runner.junit5)
    testImplementation(libs.kotest.assertions.core)
    testImplementation(libs.kotest.property)
    testImplementation(libs.testcontainers.postgresql)
    testImplementation(libs.ktor.server.test.host)
}

// The JSON examples both this service and the Elm app are tested against.
val contractExamples = rootProject.layout.projectDirectory.dir("../contract/examples")

tasks.test {
    useJUnitPlatform()
    inputs.dir(contractExamples).withPropertyName("contractExamples")
    systemProperty("contract.examples", contractExamples.asFile.absolutePath)
}
