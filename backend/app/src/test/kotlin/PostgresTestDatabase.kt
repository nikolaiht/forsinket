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
}
