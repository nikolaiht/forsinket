package io.github.nikolaiht.forsinket.app.store

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import org.flywaydb.core.Flyway
import java.sql.Connection
import javax.sql.DataSource

fun dataSource(url: String, user: String, password: String): HikariDataSource =
    HikariDataSource(
        HikariConfig().apply {
            jdbcUrl = url
            username = user
            this.password = password
            maximumPoolSize = 5
        },
    )

/** Brings the schema up to date with the migrations in `db/migration`. Safe to run at every start. */
fun migrate(dataSource: DataSource) {
    Flyway.configure().dataSource(dataSource).load().migrate()
}

/** Runs [block] in one transaction: committed if it returns, rolled back if it throws. */
inline fun <T> DataSource.transaction(block: (Connection) -> T): T =
    connection.use { connection ->
        connection.autoCommit = false
        try {
            block(connection).also { connection.commit() }
        } catch (e: Exception) {
            connection.rollback()
            throw e
        }
    }
