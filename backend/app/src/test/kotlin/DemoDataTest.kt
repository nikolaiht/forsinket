package io.github.nikolaiht.forsinket.app

import arrow.core.toNonEmptyListOrNull
import io.github.nikolaiht.forsinket.app.demo.prepareDemo
import io.github.nikolaiht.forsinket.app.demo.seedDemoData
import io.github.nikolaiht.forsinket.app.store.PostgresClaimStore
import io.github.nikolaiht.forsinket.app.traffic.SyntheticTrafficData
import io.github.nikolaiht.forsinket.domain.ClaimState
import io.github.nikolaiht.forsinket.domain.RulesV1
import io.github.nikolaiht.forsinket.domain.StatusName
import io.github.nikolaiht.forsinket.domain.replay
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldContainAll
import io.kotest.matchers.shouldBe
import java.time.Instant
import kotlin.time.Duration
import kotlin.time.Duration.Companion.minutes

class DemoDataTest : FunSpec({
    val store = PostgresClaimStore(PostgresTestDatabase.dataSource)
    val now = Instant.parse("2026-11-26T10:00:00Z")

    beforeTest { PostgresTestDatabase.empty() }

    suspend fun seed(at: Instant = now) = seedDemoData(store, SyntheticTrafficData, RulesV1, at)

    suspend fun startUp(at: Instant, resetEvery: Duration?) =
        prepareDemo(store, SyntheticTrafficData, RulesV1, at, resetEvery)

    fun someoneAddsAClaim() {
        val theirs = ContractFixtures.approvedAutomatically
        store.append(theirs.id, 0, theirs.events.toNonEmptyListOrNull()!!, summarize(theirs))
    }

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

    test("at start-up, a demo that never resets is seeded once and then left alone") {
        startUp(now, resetEvery = null)
        val first = store.summaries(null)
        first.size shouldBe 6

        startUp(now.plusSeconds(86_400), resetEvery = null)

        store.summaries(null) shouldBe first
    }

    test("at start-up, a demo that resets starts over when the last time was that long ago") {
        startUp(now, resetEvery = 60.minutes)
        someoneAddsAClaim()
        store.count() shouldBe 7

        startUp(now.plusSeconds(3600), resetEvery = 60.minutes)

        store.count() shouldBe 6
        store.load(ContractFixtures.idA) shouldBe emptyList()
    }

    test("at start-up, a demo that started over more recently than that is left as it is") {
        startUp(now, resetEvery = 60.minutes)
        someoneAddsAClaim()

        startUp(now.plusSeconds(3599), resetEvery = 60.minutes)

        store.count() shouldBe 7
    }

    test("at start-up, a demo that was emptied but never got its claims gets them") {
        store.reset(now = now, notSince = now)

        startUp(now.plusSeconds(600), resetEvery = 60.minutes)

        store.count() shouldBe 6
    }

    test("after a reset the demo claims are seeded even if someone got a claim in first") {
        someoneAddsAClaim()

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
            PostgresTestDatabase.empty()

            seed(now.plusSeconds(day * 86_400))

            store.count() shouldBe 6
        }
    }
})
