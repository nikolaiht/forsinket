package io.github.nikolaiht.forsinket.app.store

import com.zaxxer.hikari.HikariConfig
import com.zaxxer.hikari.HikariDataSource
import org.flywaydb.core.Flyway
import java.sql.Connection
import java.sql.SQLException
import javax.sql.DataSource

fun dataSource(url: String, user: String, password: String): HikariDataSource =
    HikariDataSource(
        HikariConfig().apply {
            jdbcUrl = url
            username = user
            this.password = password
            maximumPoolSize = 5
            // One connection is opened at the start, and more when they are
            // needed. A host may start several instances of the service for
            // one burst of visitors, and each of them is here only briefly.
            minimumIdle = 1
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
            try {
                connection.rollback()
            } catch (rollbackFailure: SQLException) {
                // The first failure is the one to report. This one goes along with it.
                e.addSuppressed(rollbackFailure)
            }
            throw e
        }
    }
