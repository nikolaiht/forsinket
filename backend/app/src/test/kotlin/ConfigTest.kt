package io.github.nikolaiht.forsinket.app

import arrow.core.left
import arrow.core.nonEmptyListOf
import arrow.core.right
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import java.nio.file.Path
import kotlin.time.Duration.Companion.minutes

class ConfigTest : FunSpec({
    val database = mapOf(
        "DATABASE_URL" to "jdbc:postgresql://localhost:5432/forsinket",
        "DATABASE_USER" to "forsinket",
        "DATABASE_PASSWORD" to "local-only",
    )
    val databaseConfig = DatabaseConfig("jdbc:postgresql://localhost:5432/forsinket", "forsinket", "local-only")

    test("only the database has to be configured") {
        configFrom(database) shouldBe
            Config(port = 8080, database = databaseConfig, webRoot = null, demo = null).right()
    }

    test("everything can be configured") {
        val env = database + mapOf(
            "PORT" to "9000",
            "WEB_ROOT" to "/app/web",
            "DEMO_MODE" to "true",
            "DEMO_MAX_CLAIMS" to "50",
            "DEMO_RESET_MINUTES" to "60",
        )

        configFrom(env) shouldBe
            Config(
                port = 9000,
                database = databaseConfig,
                webRoot = Path.of("/app/web"),
                demo = DemoConfig(resetEvery = 60.minutes, maxClaims = 50),
            ).right()
    }

    test("a database address of the kind a host hands out carries the user and the password") {
        val env = mapOf("DATABASE_URL" to "postgresql://forsinket:s3cret@db.example.com/forsinket?sslmode=require")

        configFrom(env).map { it.database } shouldBe
            DatabaseConfig("jdbc:postgresql://db.example.com/forsinket?sslmode=require", "forsinket", "s3cret").right()
    }

    test("such an address can have a port, and characters written with percent signs") {
        val env = mapOf("DATABASE_URL" to "postgres://for%40sinket:p%2Bss%3Aw+rd@db.example.com:6543/forsinket")

        configFrom(env).map { it.database } shouldBe
            DatabaseConfig("jdbc:postgresql://db.example.com:6543/forsinket", "for@sinket", "p+ss:w+rd").right()
    }

    test("the direct connection is used when a host offers one beside a pooled one") {
        val env = mapOf(
            "DATABASE_URL" to "postgresql://forsinket:s3cret@pooler.example.com/forsinket",
            "DATABASE_URL_UNPOOLED" to "postgresql://forsinket:s3cret@db.example.com/forsinket",
        )

        configFrom(env).map { it.database.url } shouldBe "jdbc:postgresql://db.example.com/forsinket".right()
    }

    test("a database address that cannot be used is a problem, and the problem does not repeat the password") {
        val unusable = listOf(
            "mysql://forsinket:s3cret@db.example.com/forsinket",
            "postgresql://forsinket:s3cret@db.example.com",
            "postgresql://forsinket@db.example.com/forsinket",
            "postgresql://db.example.com/forsinket",
            "postgresql://forsinket:s3cret@/forsinket",
            "postgresql://forsinket:s3cret@db.example.com/for sinket",
        )

        unusable.forEach { address ->
            configFrom(mapOf("DATABASE_URL" to address)) shouldBe
                nonEmptyListOf(
                    "DATABASE_URL must be a jdbc:postgresql: address, " +
                        "or a postgresql: address with the user and the password in it",
                ).left()
        }
    }

    test("an empty WEB_ROOT means no web app, not the working directory") {
        configFrom(database + ("WEB_ROOT" to "  ")).map { it.webRoot } shouldBe null.right()
    }

    test("demo mode has a cap on claims and no reset unless one is asked for") {
        configFrom(database + ("DEMO_MODE" to "true")).map { it.demo } shouldBe
            DemoConfig(resetEvery = null, maxClaims = 500).right()
    }

    test("demo settings mean nothing when demo mode is off") {
        configFrom(database + ("DEMO_RESET_MINUTES" to "60")).map { it.demo } shouldBe null.right()
    }

    test("every problem is reported at once") {
        val env = mapOf("DATABASE_USER" to "forsinket", "PORT" to "http", "DEMO_MODE" to "yes")

        configFrom(env) shouldBe
            nonEmptyListOf(
                "PORT must be a whole number between 1 and 65535, was 'http'",
                "DATABASE_URL is required",
                "DATABASE_PASSWORD is required",
                "DEMO_MODE must be 'true' or 'false', was 'yes'",
            ).left()
    }

    test("numbers outside their range are problems") {
        val env =
            database +
                mapOf("PORT" to "0", "DEMO_MODE" to "true", "DEMO_MAX_CLAIMS" to "0", "DEMO_RESET_MINUTES" to "-5")

        configFrom(env) shouldBe
            nonEmptyListOf(
                "PORT must be a whole number between 1 and 65535, was '0'",
                "DEMO_MAX_CLAIMS must be a whole number of at least 1, was '0'",
                "DEMO_RESET_MINUTES must be a whole number of at least 1, was '-5'",
            ).left()
    }
})
