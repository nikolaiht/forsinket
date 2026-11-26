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
}

tasks.test {
    useJUnitPlatform()
}
