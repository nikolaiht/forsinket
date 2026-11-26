package io.github.nikolaiht.forsinket.app

import arrow.core.Either
import arrow.core.NonEmptyList
import arrow.core.left
import io.github.nikolaiht.forsinket.app.store.ClaimStore
import io.github.nikolaiht.forsinket.app.store.VersionConflict
import io.github.nikolaiht.forsinket.app.traffic.SyntheticTrafficData
import io.github.nikolaiht.forsinket.domain.Assessment
import io.github.nikolaiht.forsinket.domain.ClaimDraft
import io.github.nikolaiht.forsinket.domain.ClaimEvent
import io.github.nikolaiht.forsinket.domain.ClaimId
import io.github.nikolaiht.forsinket.domain.ClaimState
import io.github.nikolaiht.forsinket.domain.DecisionChoiceDraft
import io.github.nikolaiht.forsinket.domain.DecisionDraft
import io.github.nikolaiht.forsinket.domain.ExpensesDraft
import io.github.nikolaiht.forsinket.domain.Handling
import io.github.nikolaiht.forsinket.domain.Rejection
import io.github.nikolaiht.forsinket.domain.RulesV1
import io.github.nikolaiht.forsinket.domain.StatusName
import io.github.nikolaiht.forsinket.domain.TicketDraft
import io.github.nikolaiht.forsinket.domain.shouldBeRight
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.property.Arb
import io.kotest.property.arbitrary.bind
import io.kotest.property.arbitrary.element
import io.kotest.property.arbitrary.int
import io.kotest.property.arbitrary.long
import io.kotest.property.arbitrary.orNull
import io.kotest.property.checkAll
import java.time.Instant
import java.time.LocalDate
import java.util.UUID

class ClaimServiceTest : FunSpec({
    val fixtures = ContractFixtures

    fun service(store: ClaimStore, now: Instant = fixtures.submittedA, id: ClaimId = ClaimId(UUID.randomUUID())) =
        ClaimService(store, SyntheticTrafficData, RulesV1, TestClock(now), newId = { id }, maxClaims = null)

    test("a writer that gets in between the read and the write is reported as a conflict, like one that got in before") {
        // The claim is at version 2 when it is read, and at version 3 by the time the decision is written.
        val store = object : ClaimStore by InMemoryClaimStore() {
            override fun load(id: ClaimId): List<ClaimEvent> = fixtures.awaitingReview.events

            override fun append(
                id: ClaimId,
                expectedVersion: Int,
                events: NonEmptyList<ClaimEvent>,
                summary: ClaimSummary,
            ): Either<VersionConflict, Int> = VersionConflict(currentVersion = 3).left()
        }
        val approve = DecisionDraft("KN", "", DecisionChoiceDraft.Approve(50000))

        service(store).decide(fixtures.idB, expectedVersion = 2, approve) shouldBe
            ApiError.VersionConflict(currentVersion = 3).left()
    }

    test("what the preview says is what submitting records") {
        // Dates from long before the deadline to just after it, so that all three outcomes occur.
        val drafts = Arb.bind(
            Arb.int(0..100),
            Arb.element("TB11", "TB12", "TB13", "TB14", "TB15", "TB16", "TB17", "TB18"),
            Arb.long(1L..2_000_000L),
            Arb.long(1L..1_000_000L).orNull(0.5),
        ) { daysAgo, train, price, expenses ->
            val day = LocalDate.of(2026, 11, 20).minusDays(daysAgo.toLong())
            ClaimDraft("$day-$train", TicketDraft.Single(price), expenses?.let { ExpensesDraft(it, "taxi") })
        }

        checkAll(drafts) { draft ->
            val service = service(InMemoryClaimStore(), now = Instant.parse("2026-11-21T09:15:00Z"))

            val preview = service.preview(draft).shouldBeRight()
            val state = service.submit(draft).shouldBeRight().state

            when (preview) {
                is Assessment.NotEligible ->
                    (state as ClaimState.Rejected).rejection shouldBe Rejection.ByRules(preview.reason)

                is Assessment.Eligible ->
                    when (val handling = preview.handling) {
                        Handling.AutoApprove ->
                            (state as ClaimState.Approved).calculation shouldBe preview.calculation

                        is Handling.ManualReview -> {
                            (state as ClaimState.AwaitingReview).calculation shouldBe preview.calculation
                            state.reasons shouldBe handling.reasons
                        }
                    }
            }
        }
    }

    test("the departures of a day are the ones that were due to leave by now") {
        val service = service(InMemoryClaimStore(), now = Instant.parse("2026-11-20T12:00:00Z")) // 13:00 in Oslo

        service.departures(LocalDate.of(2026, 11, 20)).map { it.trainNumber } shouldBe
            listOf("TB11", "TB12", "TB13", "TB14")
        service.departures(LocalDate.of(2026, 11, 21)) shouldBe emptyList()
    }

    test("a claim is listed with the status it has") {
        val store = InMemoryClaimStore()
        val service = service(store, id = fixtures.idA)

        service.submit(ClaimDraft("2026-11-20-TB16", TicketDraft.Single(34900), null)).shouldBeRight()

        service.list(StatusName.APPROVED).map { it.id } shouldBe listOf(fixtures.idA)
        service.list(StatusName.REJECTED) shouldBe emptyList()
    }
})
