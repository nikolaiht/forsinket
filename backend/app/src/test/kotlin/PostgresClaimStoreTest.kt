package io.github.nikolaiht.forsinket.app

import arrow.core.left
import arrow.core.nonEmptyListOf
import arrow.core.right
import arrow.core.toNonEmptyListOrNull
import io.github.nikolaiht.forsinket.app.store.PostgresClaimStore
import io.github.nikolaiht.forsinket.app.store.VersionConflict
import io.github.nikolaiht.forsinket.app.store.migrate
import io.github.nikolaiht.forsinket.domain.ClaimEvent
import io.github.nikolaiht.forsinket.domain.ClaimId
import io.github.nikolaiht.forsinket.domain.ClaimState
import io.github.nikolaiht.forsinket.domain.StatusName
import io.github.nikolaiht.forsinket.domain.replay
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import java.time.Instant
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

class PostgresClaimStoreTest : FunSpec({
    val dataSource = PostgresTestDatabase.dataSource
    val store = PostgresClaimStore(dataSource)
    val fixtures = ContractFixtures
    val noon = Instant.parse("2026-11-26T12:00:00Z")

    beforeTest { PostgresTestDatabase.empty() }

    fun ClaimSnapshot.eventsAfter(version: Int) =
        events.drop(version).toNonEmptyListOrNull() ?: error("no events after version $version")

    /** Appends the events a snapshot has beyond [expectedVersion], with the snapshot's summary. */
    fun append(snapshot: ClaimSnapshot, expectedVersion: Int = 0) =
        store.append(snapshot.id, expectedVersion, snapshot.eventsAfter(expectedVersion), summarize(snapshot))

    /** The claim as the store has it, rebuilt from its events. */
    fun stored(id: ClaimId): ClaimSnapshot {
        val events = store.load(id)
        return checkNotNull(snapshotOf(id, events))
    }

    test("events are read back in the order they were written") {
        append(fixtures.awaitingReview) shouldBe 2.right()
        append(fixtures.approvedByOfficer, expectedVersion = 2) shouldBe 3.right()

        store.load(fixtures.idB) shouldBe fixtures.approvedByOfficer.events
    }

    test("a claim nobody has submitted has no events") {
        store.load(ClaimId(UUID.randomUUID())) shouldBe emptyList()
    }

    test("claims do not see each other's events") {
        append(fixtures.approvedAutomatically)
        append(fixtures.awaitingReview)

        store.load(fixtures.idA) shouldBe fixtures.approvedAutomatically.events
        store.load(fixtures.idB) shouldBe fixtures.awaitingReview.events
    }

    test("a writer that built on an old version is turned away, and nothing is written") {
        append(fixtures.awaitingReview)
        append(fixtures.approvedByOfficer, expectedVersion = 2)

        // A second officer who still sees version 2 tries to reject.
        append(fixtures.rejectedByOfficer, expectedVersion = 2) shouldBe VersionConflict(currentVersion = 3).left()

        stored(fixtures.idB) shouldBe fixtures.approvedByOfficer
        store.summaries(null) shouldBe listOf(summarize(fixtures.approvedByOfficer))
    }

    test("a claim that already exists cannot be created again") {
        append(fixtures.approvedAutomatically)

        append(fixtures.approvedAutomatically) shouldBe VersionConflict(currentVersion = 2).left()
    }

    test("a writer that loses the race inside the database gets a conflict, not an exception") {
        val id = ClaimId(UUID.randomUUID())
        val payout = nonEmptyListOf<ClaimEvent>(ClaimEvent.PayoutRecorded(fixtures.paidAt))
        val summary = summarize(fixtures.paidOut).copy(id = id)

        dataSource.connection.use { winner ->
            // The winner has written version 1 but not committed, so the loser
            // still reads version 0 and goes on to insert the same version.
            winner.autoCommit = false
            winner.prepareStatement(
                """
                INSERT INTO claim_events (claim_id, version, event_type, payload, occurred_at)
                VALUES (?, 1, 'payout_recorded', '{"type":"payout_recorded","at":"2026-11-22T08:00:00Z"}', now())
                """.trimIndent(),
            ).use { statement ->
                statement.setObject(1, id.value)
                statement.executeUpdate()
            }

            val loser = CompletableFuture.supplyAsync { store.append(id, expectedVersion = 0, payout, summary) }
            awaitBlocked(sessions = 1)
            winner.commit()

            loser.get(10, TimeUnit.SECONDS) shouldBe VersionConflict(currentVersion = 1).left()
        }
        store.summaries(null) shouldBe emptyList()
    }

    test("summaries are listed newest first") {
        append(fixtures.approvedAutomatically)
        append(fixtures.awaitingReview)
        append(fixtures.rejectedByRules)

        store.summaries(null) shouldBe
            listOf(fixtures.rejectedByRules, fixtures.awaitingReview, fixtures.approvedAutomatically).map(::summarize)
    }

    test("summaries can be filtered by status") {
        append(fixtures.approvedAutomatically)
        append(fixtures.awaitingReview)
        append(fixtures.rejectedByRules)

        store.summaries(StatusName.AWAITING_REVIEW) shouldBe listOf(summarize(fixtures.awaitingReview))
        store.summaries(StatusName.PAID_OUT) shouldBe emptyList()
    }

    test("the summary follows the claim as it changes") {
        append(fixtures.awaitingReview)
        store.summaries(null) shouldBe listOf(summarize(stored(fixtures.idB)))

        append(fixtures.approvedByOfficer, expectedVersion = 2)
        store.summaries(null) shouldBe listOf(summarize(stored(fixtures.idB)))
        store.summaries(null).single().status shouldBe StatusName.APPROVED
    }

    test("a reset removes every claim") {
        append(fixtures.approvedAutomatically)
        append(fixtures.awaitingReview)
        store.count() shouldBe 2

        store.reset(now = noon, notSince = noon) shouldBe true

        store.count() shouldBe 0
        store.load(fixtures.idA) shouldBe emptyList()
    }

    test("a reset that has already been done since the given time is not done again") {
        store.reset(now = noon, notSince = noon)
        append(fixtures.approvedAutomatically)

        store.reset(now = noon.plusSeconds(600), notSince = noon.minusSeconds(3000)) shouldBe false

        store.count() shouldBe 1
    }

    test("a reset is done again when the last one was at the given time or before it") {
        store.reset(now = noon, notSince = noon)
        append(fixtures.approvedAutomatically)

        store.reset(now = noon.plusSeconds(3600), notSince = noon) shouldBe true

        store.count() shouldBe 0
    }

    test("of two resets asked for at the same moment, only one is done") {
        val results = dataSource.connection.use { holder ->
            // Someone else holds the lock the resets queue up behind, so both
            // are waiting before either has looked at when the last one was.
            holder.autoCommit = false
            holder.createStatement().use { it.execute("LOCK TABLE demo_resets IN EXCLUSIVE MODE") }

            val resets = List(2) {
                CompletableFuture.supplyAsync { store.reset(now = noon, notSince = noon.minusSeconds(3600)) }
            }
            awaitBlocked(sessions = 2)
            holder.commit()

            resets.map { it.get(10, TimeUnit.SECONDS) }
        }

        results.sorted() shouldBe listOf(false, true)
    }

    test("migrating a database that is already migrated changes nothing") {
        append(fixtures.approvedAutomatically)

        migrate(dataSource)

        store.count() shouldBe 1
    }
}) {
    companion object {
        /** Waits until this many sessions in the database are blocked on a lock held by another. */
        private fun awaitBlocked(sessions: Int) {
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)
            PostgresTestDatabase.dataSource.connection.use { connection ->
                connection.prepareStatement("SELECT count(*) FROM pg_locks WHERE NOT granted").use { statement ->
                    while (System.nanoTime() < deadline) {
                        val blocked = statement.executeQuery().use {
                            it.next()
                            it.getInt(1)
                        }
                        if (blocked >= sessions) return
                        Thread.sleep(20)
                    }
                }
            }
            error("fewer than $sessions sessions became blocked within ten seconds")
        }
    }
}
