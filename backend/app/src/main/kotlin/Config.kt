package io.github.nikolaiht.forsinket.app

import arrow.core.EitherNel
import arrow.core.NonEmptyList
import arrow.core.nel
import arrow.core.raise.Raise
import arrow.core.raise.either
import arrow.core.raise.ensure
import arrow.core.raise.ensureNotNull
import arrow.core.raise.zipOrAccumulate
import java.net.URI
import java.net.URISyntaxException
import java.net.URLDecoder
import java.nio.file.Path
import kotlin.time.Duration
import kotlin.time.Duration.Companion.minutes

data class Config(
    val port: Int,
    val database: DatabaseConfig,
    val webRoot: Path?,
    val demo: DemoConfig?,
)

data class DatabaseConfig(
    val url: String,
    val user: String,
    val password: String,
)

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
            { withNel { database(env) } },
            { withNel { demo(env) } },
        ) { port, database, demo ->
            val webRoot = env["WEB_ROOT"]?.takeIf { it.isNotBlank() }?.let(Path::of)
            Config(port, database, webRoot, demo)
        }
    }

/**
 * The database can be given in two ways. Locally it is a JDBC address, with
 * the user and the password beside it. A hosting platform usually hands out
 * one `postgresql://user:password@host/database` address, and that is read as
 * it is.
 *
 * A platform that puts a connection pooler in front of the database gives the
 * direct address in `DATABASE_URL_UNPOOLED`. That one is used when it is
 * there: this service keeps its own pool of connections, and has no use for a
 * second pool in front of it.
 */
private fun Raise<NonEmptyList<String>>.database(env: Map<String, String>): DatabaseConfig {
    val name = if (env["DATABASE_URL_UNPOOLED"].isNullOrBlank()) "DATABASE_URL" else "DATABASE_URL_UNPOOLED"
    val address = env[name].orEmpty()

    return if (address.isBlank() || address.startsWith(JDBC_PREFIX)) {
        zipOrAccumulate(
            { required(env, name) },
            { required(env, "DATABASE_USER") },
            { required(env, "DATABASE_PASSWORD") },
            ::DatabaseConfig,
        )
    } else {
        // The address is not repeated in the message: it has a password in it.
        hostedDatabase(address) ?: raise(
            "$name must be a jdbc:postgresql: address, or a postgresql: address with the user and the password in it"
                .nel(),
        )
    }
}

/** Reads `postgresql://user:password@host:port/database?options`, or gives null when the text is not that. */
private fun hostedDatabase(address: String): DatabaseConfig? {
    val uri = try {
        URI(address)
    } catch (_: URISyntaxException) {
        return null
    }
    val credentials = uri.rawUserInfo?.split(":", limit = 2).orEmpty()
    val database = uri.rawPath.orEmpty()
    if (uri.scheme !in HOSTED_SCHEMES || uri.host == null || credentials.size != 2 || database.length < 2) return null

    val port = if (uri.port == -1) "" else ":${uri.port}"
    val options = uri.rawQuery?.let { "?$it" }.orEmpty()
    return DatabaseConfig(
        url = "$JDBC_PREFIX//${uri.host}$port$database$options",
        user = percentDecoded(credentials[0]),
        password = percentDecoded(credentials[1]),
    )
}

/** A plus sign stands for itself in an address. URLDecoder reads it as a space, which is right only for forms. */
private fun percentDecoded(text: String): String = URLDecoder.decode(text.replace("+", "%2B"), Charsets.UTF_8)

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

private const val JDBC_PREFIX = "jdbc:postgresql:"
private val HOSTED_SCHEMES = setOf("postgresql", "postgres")
private const val DEFAULT_PORT = 8080
private const val DEFAULT_MAX_CLAIMS = 500
private val PORTS = 1..65535
private val POSITIVE = 1..Int.MAX_VALUE
