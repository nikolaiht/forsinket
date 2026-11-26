package io.github.nikolaiht.forsinket.app

import io.github.nikolaiht.forsinket.app.demo.seedDemoData
import io.github.nikolaiht.forsinket.app.store.PostgresClaimStore
import io.github.nikolaiht.forsinket.app.traffic.SyntheticTrafficData
import io.github.nikolaiht.forsinket.domain.ClaimState
import io.github.nikolaiht.forsinket.domain.RulesV1
import io.github.nikolaiht.forsinket.domain.StatusName
import io.github.nikolaiht.forsinket.domain.dateIn2026
import io.github.nikolaiht.forsinket.domain.replay
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldContainAll
import io.kotest.matchers.shouldBe
import io.kotest.property.Arb
import io.kotest.property.checkAll
import java.time.Instant
import java.time.ZoneOffset

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
            val snapshot = ClaimSnapshot(summary.id, events.size, replay(events) as ClaimState.Filed, events)

            summarize(snapshot) shouldBe summary
        }
    }

    test("seeding again gives the same claims, not more of them") {
        seed()
        val first = store.summaries(null)

        seed()

        store.summaries(null) shouldBe first
    }

    test("every seeded claim was submitted before now, and none is too late") {
        seed()

        store.summaries(null).forEach { summary ->
            (summary.submittedAt < now) shouldBe true
        }
        store.summaries(StatusName.REJECTED).size shouldBe 2
    }

    test("the demo can be seeded on any day of the year") {
        checkAll(14, Arb.dateIn2026()) { date ->
            store.reset()

            seed(date.atTime(10, 0).toInstant(ZoneOffset.UTC))

            store.count() shouldBe 6
        }
    }
})
