package io.github.nikolaiht.forsinket.app

import com.zaxxer.hikari.HikariDataSource
import io.github.nikolaiht.forsinket.app.store.dataSource
import io.github.nikolaiht.forsinket.app.store.migrate
import org.testcontainers.postgresql.PostgreSQLContainer

/**
 * A real PostgreSQL for the tests: one container for the whole test run,
 * started the first time a test asks for it, with the migrations applied.
 * Tests share the database and empty it before each test.
 */
object PostgresTestDatabase {
    val dataSource: HikariDataSource by lazy {
        val container = PostgreSQLContainer("postgres:18-alpine")
        container.start()
        dataSource(container.jdbcUrl, container.username, container.password).also(::migrate)
    }

    /** Removes everything the tests have stored, so that a test starts with an empty database. */
    fun empty() {
        dataSource.connection.use { connection ->
            connection.createStatement().use { it.execute("TRUNCATE claim_events, claim_summaries, demo_resets") }
        }
    }
}
