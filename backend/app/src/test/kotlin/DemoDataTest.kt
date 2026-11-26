package io.github.nikolaiht.forsinket.app

import io.github.nikolaiht.forsinket.app.demo.seedDemoData
import io.github.nikolaiht.forsinket.app.demo.seedIfEmpty
import io.github.nikolaiht.forsinket.app.store.PostgresClaimStore
import io.github.nikolaiht.forsinket.app.traffic.SyntheticTrafficData
import io.github.nikolaiht.forsinket.domain.ClaimState
import io.github.nikolaiht.forsinket.domain.RulesV1
import io.github.nikolaiht.forsinket.domain.StatusName
import io.github.nikolaiht.forsinket.domain.replay
import arrow.core.toNonEmptyListOrNull
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldContainAll
import io.kotest.matchers.shouldBe
import java.time.Instant

class DemoDataTest : FunSpec({
    val store = PostgresClaimStore(PostgresTestDatabase.dataSource)
    val now = Instant.parse("2026-11-26T10:00:00Z")

    beforeTest { store.reset() }

    suspend fun seed(at: Instant = now) = seedDemoData(store, SyntheticTrafficData, RulesV1, at)

    test("the demo starts with claims in every status a claim can rest in") {
        seed()

        store.summaries(null).map { it.status } shouldContainAll
            listOf(StatusName.AWAITING_REVIEW, StatusName.APPROVED, StatusName.REJECTED, StatusName.PAID_OUT)
    }

    test("the seeded claims went through the same rules as any other claim") {
        seed()

        store.summaries(null).forEach { summary ->
            val events = store.load(summary.id)
            val snapshot = checkNotNull(snapshotOf(summary.id, events))

            summarize(snapshot) shouldBe summary
        }
    }

    test("at start-up, a store that already has claims is left alone") {
        seedIfEmpty(store, SyntheticTrafficData, RulesV1, now)
        val first = store.summaries(null)

        seedIfEmpty(store, SyntheticTrafficData, RulesV1, now.plusSeconds(3600))

        store.summaries(null) shouldBe first
    }

    test("after a reset the demo claims are seeded even if someone got a claim in first") {
        val someoneElses = ContractFixtures.approvedAutomatically
        store.append(someoneElses.id, 0, someoneElses.events.toNonEmptyListOrNull()!!, summarize(someoneElses))

        seed()

        store.count() shouldBe 7
    }

    test("every seeded claim was submitted before now, and none is too late") {
        seed()

        store.summaries(null).forEach { summary ->
            (summary.submittedAt < now) shouldBe true
        }
        store.summaries(StatusName.REJECTED).size shouldBe 2
    }

    test("the demo can be seeded on every day of the week, whatever the traffic was") {
        (0L..6L).forEach { day ->
            store.reset()

            seed(now.plusSeconds(day * 86_400))

            store.count() shouldBe 6
        }
    }
})
