package io.github.nikolaiht.forsinket.app.store

import arrow.core.Either
import arrow.core.NonEmptyList
import arrow.core.left
import arrow.core.right
import io.github.nikolaiht.forsinket.app.ClaimSummary
import io.github.nikolaiht.forsinket.app.json.StoredEvent
import io.github.nikolaiht.forsinket.app.json.StoredJson
import io.github.nikolaiht.forsinket.app.json.storedEnum
import io.github.nikolaiht.forsinket.app.json.toDomain
import io.github.nikolaiht.forsinket.app.json.toStored
import io.github.nikolaiht.forsinket.domain.ClaimEvent
import io.github.nikolaiht.forsinket.domain.ClaimId
import io.github.nikolaiht.forsinket.domain.Money
import io.github.nikolaiht.forsinket.domain.StatusName
import io.github.nikolaiht.forsinket.domain.wireName
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.sql.Connection
import java.sql.ResultSet
import java.sql.SQLException
import java.sql.Types
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID
import javax.sql.DataSource

class PostgresClaimStore(private val dataSource: DataSource) : ClaimStore {
    override fun load(id: ClaimId): List<ClaimEvent> =
        dataSource.connection.use { connection ->
            connection.prepareStatement(
                "SELECT payload FROM claim_events WHERE claim_id = ? ORDER BY version",
            ).use { statement ->
                statement.setObject(1, id.value)
                statement.executeQuery().use { rows ->
                    rows.map { StoredJson.decodeFromString(StoredEvent.serializer(), it.getString("payload")).toDomain() }
                }
            }
        }

    override fun append(
        id: ClaimId,
        expectedVersion: Int,
        events: NonEmptyList<ClaimEvent>,
        summary: ClaimSummary,
    ): Either<VersionConflict, Int> {
        require(summary.id == id) { "the summary of claim ${summary.id.value} was given for claim ${id.value}" }
        return try {
            dataSource.transaction { connection ->
                val currentVersion = connection.currentVersion(id)
                if (currentVersion != expectedVersion) {
                    VersionConflict(currentVersion).left()
                } else {
                    events.forEachIndexed { index, event ->
                        connection.insertEvent(id, version = expectedVersion + index + 1, event)
                    }
                    connection.upsertSummary(summary)
                    (expectedVersion + events.size).right()
                }
            }
        } catch (e: SQLException) {
            // Two writers both read the same version, and the other one inserted
            // first. The primary key on (claim_id, version) stopped this one.
            if (e.sqlState != UNIQUE_VIOLATION) throw e
            VersionConflict(dataSource.connection.use { it.currentVersion(id) }).left()
        }
    }

    override fun summaries(status: StatusName?): List<ClaimSummary> =
        dataSource.connection.use { connection ->
            connection.prepareStatement(
                """
                SELECT claim_id, version, status, submitted_at, departure_date, train_number, total_ore
                FROM claim_summaries
                WHERE status = COALESCE(?, status)
                ORDER BY submitted_at DESC, claim_id
                """.trimIndent(),
            ).use { statement ->
                statement.setString(1, status?.wireName)
                statement.executeQuery().use { rows -> rows.map(::summary) }
            }
        }

    override fun count(): Int =
        dataSource.connection.use { connection ->
            connection.prepareStatement("SELECT count(*) FROM claim_summaries").use { statement ->
                statement.executeQuery().use { rows ->
                    rows.next()
                    rows.getInt(1)
                }
            }
        }

    override fun reset() {
        dataSource.connection.use { connection ->
            connection.prepareStatement("TRUNCATE claim_events, claim_summaries").use { it.executeUpdate() }
        }
    }

    private fun Connection.currentVersion(id: ClaimId): Int =
        prepareStatement("SELECT COALESCE(max(version), 0) FROM claim_events WHERE claim_id = ?").use { statement ->
            statement.setObject(1, id.value)
            statement.executeQuery().use { rows ->
                rows.next()
                rows.getInt(1)
            }
        }

    private fun Connection.insertEvent(id: ClaimId, version: Int, event: ClaimEvent) {
        val payload = StoredJson.encodeToJsonElement(StoredEvent.serializer(), event.toStored())
        prepareStatement(
            """
            INSERT INTO claim_events (claim_id, version, event_type, payload, occurred_at)
            VALUES (?, ?, ?, ?::jsonb, ?)
            """.trimIndent(),
        ).use { statement ->
            statement.setObject(1, id.value)
            statement.setInt(2, version)
            statement.setString(3, payload.jsonObject.getValue("type").jsonPrimitive.content)
            statement.setString(4, payload.toString())
            statement.setObject(5, event.at.atOffset(ZoneOffset.UTC))
            statement.executeUpdate()
        }
    }

    private fun Connection.upsertSummary(summary: ClaimSummary) {
        prepareStatement(
            """
            INSERT INTO claim_summaries
                (claim_id, version, status, submitted_at, departure_date, train_number, total_ore)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (claim_id) DO UPDATE SET
                version = EXCLUDED.version,
                status = EXCLUDED.status,
                total_ore = EXCLUDED.total_ore
            """.trimIndent(),
        ).use { statement ->
            statement.setObject(1, summary.id.value)
            statement.setInt(2, summary.version)
            statement.setString(3, summary.status.wireName)
            statement.setObject(4, summary.submittedAt.atOffset(ZoneOffset.UTC))
            statement.setObject(5, summary.departureDate)
            statement.setString(6, summary.trainNumber)
            statement.setObject(7, summary.total?.ore, Types.BIGINT)
            statement.executeUpdate()
        }
    }

    private fun summary(row: ResultSet): ClaimSummary =
        ClaimSummary(
            id = ClaimId(row.getObject("claim_id", UUID::class.java)),
            version = row.getInt("version"),
            status = storedEnum<StatusName>(row.getString("status")),
            submittedAt = row.getObject("submitted_at", OffsetDateTime::class.java).toInstant(),
            departureDate = row.getObject("departure_date", LocalDate::class.java),
            trainNumber = row.getString("train_number"),
            total = row.getLong("total_ore").takeUnless { row.wasNull() }?.let(Money::ofOre),
        )

    private companion object {
        /** PostgreSQL's SQLSTATE for a violated unique constraint. */
        const val UNIQUE_VIOLATION = "23505"
    }
}

private inline fun <T> ResultSet.map(transform: (ResultSet) -> T): List<T> =
    buildList {
        while (next()) add(transform(this@map))
    }
