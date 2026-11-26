package io.github.nikolaiht.forsinket.app

import io.github.nikolaiht.forsinket.app.store.PostgresClaimStore
import io.github.nikolaiht.forsinket.app.traffic.SyntheticTrafficData
import io.github.nikolaiht.forsinket.domain.ClaimDraft
import io.github.nikolaiht.forsinket.domain.ClaimId
import io.github.nikolaiht.forsinket.domain.ClaimState
import io.github.nikolaiht.forsinket.domain.DecisionChoiceDraft
import io.github.nikolaiht.forsinket.domain.DecisionDraft
import io.github.nikolaiht.forsinket.domain.ExpensesDraft
import io.github.nikolaiht.forsinket.domain.RejectionReason
import io.github.nikolaiht.forsinket.domain.RulesV1
import io.github.nikolaiht.forsinket.domain.TicketDraft
import io.github.nikolaiht.forsinket.domain.wireName
import io.github.nikolaiht.forsinket.domain.replay
import io.github.nikolaiht.forsinket.domain.shouldBeRight
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.property.Arb
import io.kotest.property.arbitrary.bind
import io.kotest.property.arbitrary.choice
import io.kotest.property.arbitrary.constant
import io.kotest.property.arbitrary.element
import io.kotest.property.arbitrary.enum
import io.kotest.property.arbitrary.int
import io.kotest.property.arbitrary.list
import io.kotest.property.arbitrary.long
import io.kotest.property.arbitrary.map
import io.kotest.property.arbitrary.orNull
import io.kotest.property.checkAll
import java.time.Instant
import java.util.UUID

/** What can be done to a claim once it exists. */
private sealed interface Action {
    data class Decide(val draft: DecisionDraft) : Action

    data object Payout : Action
}

private val trainNumbers = listOf("TB11", "TB12", "TB13", "TB14", "TB15", "TB16", "TB17", "TB18")

/** A claim for some departure in the week before 21 November 2026. Always valid. */
private val claimDrafts: Arb<ClaimDraft> =
    Arb.bind(
        Arb.int(14..20),
        Arb.element(trainNumbers),
        Arb.long(1L..2_000_000L),
        Arb.long(1L..1_000_000L).orNull(0.5),
    ) { day, train, price, expenses ->
        ClaimDraft(
            departureId = "2026-11-$day-$train",
            ticket = TicketDraft.Single(price),
            expenses = expenses?.let { ExpensesDraft(it, "taxi") },
        )
    }

private val actions: Arb<Action> =
    Arb.choice(
        Arb.long(0L..100_000L).map { Action.Decide(DecisionDraft("KN", "", DecisionChoiceDraft.Approve(it))) },
        Arb.enum<RejectionReason>().map {
            Action.Decide(DecisionDraft("KN", "Begrunnelse", DecisionChoiceDraft.Reject(it.wireName)))
        },
        Arb.constant(Action.Payout),
    )

class ClaimServicePropertyTest : FunSpec({
    val store = PostgresClaimStore(PostgresTestDatabase.dataSource)
    val clock = TestClock(Instant.parse("2026-11-21T09:15:00Z"))

    beforeTest { store.reset() }

    test("whatever is done to a claim, its summary is what its events add up to") {
        checkAll(60, claimDrafts, Arb.list(actions, 0..5)) { draft, followUps ->
            val id = ClaimId(UUID.randomUUID())
            val service = ClaimService(store, SyntheticTrafficData, RulesV1, clock, newId = { id }, maxClaims = null)

            service.submit(draft).shouldBeRight()

            followUps.forEach { action ->
                // The outcome does not matter here: accepted or refused, the two must agree afterwards.
                val version = store.load(id).size
                when (action) {
                    is Action.Decide -> service.decide(id, version, action.draft)
                    Action.Payout -> service.recordPayout(id, version)
                }

                val events = store.load(id)
                val snapshot = checkNotNull(snapshotOf(id, events))
                store.summaries(null).single { it.id == id } shouldBe summarize(snapshot)
            }
        }
    }
})
