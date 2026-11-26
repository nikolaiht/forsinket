package io.github.nikolaiht.forsinket.app

import arrow.core.EitherNel
import arrow.core.NonEmptyList
import arrow.core.nel
import arrow.core.raise.Raise
import arrow.core.raise.either
import arrow.core.raise.ensure
import arrow.core.raise.ensureNotNull
import arrow.core.raise.zipOrAccumulate
import java.nio.file.Path
import kotlin.time.Duration
import kotlin.time.Duration.Companion.minutes

data class Config(
    val port: Int,
    val database: DatabaseConfig,
    val webRoot: Path?,
    val demo: DemoConfig?,
)

data class DatabaseConfig(val url: String, val user: String, val password: String)

/**
 * Settings for running as an open demo: seed data when the store is empty, a
 * cap on stored claims, and optionally a reset back to the seed data.
 */
data class DemoConfig(val resetEvery: Duration?, val maxClaims: Int)

/**
 * Reads the configuration from environment variables. Like the domain's
 * validation it reports every problem at once, so a deployment with three
 * mistakes fails once, not three times.
 */
fun configFrom(env: Map<String, String>): EitherNel<String, Config> =
    either {
        zipOrAccumulate(
            { number(env, "PORT", PORTS, "between 1 and 65535") ?: DEFAULT_PORT },
            { required(env, "DATABASE_URL") },
            { required(env, "DATABASE_USER") },
            { required(env, "DATABASE_PASSWORD") },
            { withNel { demo(env) } },
        ) { port, url, user, password, demo ->
            Config(port, DatabaseConfig(url, user, password), env["WEB_ROOT"]?.takeIf { it.isNotBlank() }?.let(Path::of), demo)
        }
    }

private fun Raise<NonEmptyList<String>>.demo(env: Map<String, String>): DemoConfig? {
    val enabled =
        when (val raw = env["DEMO_MODE"]) {
            null, "false" -> false
            "true" -> true
            else -> raise("DEMO_MODE must be 'true' or 'false', was '$raw'".nel())
        }
    if (!enabled) return null

    return zipOrAccumulate(
        { number(env, "DEMO_MAX_CLAIMS", POSITIVE, "of at least 1") ?: DEFAULT_MAX_CLAIMS },
        { number(env, "DEMO_RESET_MINUTES", POSITIVE, "of at least 1") },
    ) { maxClaims, resetMinutes ->
        DemoConfig(resetEvery = resetMinutes?.minutes, maxClaims = maxClaims)
    }
}

private fun Raise<String>.required(env: Map<String, String>, name: String): String =
    ensureNotNull(env[name]?.takeIf { it.isNotBlank() }) { "$name is required" }

/** A whole number in [range], or null when the variable is not set. */
private fun Raise<String>.number(env: Map<String, String>, name: String, range: IntRange, rangeText: String): Int? {
    val raw = env[name] ?: return null
    val number = raw.toIntOrNull()
    ensure(number != null && number in range) { "$name must be a whole number $rangeText, was '$raw'" }
    return number
}

private const val DEFAULT_PORT = 8080
private const val DEFAULT_MAX_CLAIMS = 500
private val PORTS = 1..65535
private val POSITIVE = 1..Int.MAX_VALUE
