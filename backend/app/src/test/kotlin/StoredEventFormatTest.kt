package io.github.nikolaiht.forsinket.app

import arrow.core.nonEmptyListOf
import io.github.nikolaiht.forsinket.app.json.StoredEvent
import io.github.nikolaiht.forsinket.app.json.StoredJson
import io.github.nikolaiht.forsinket.app.json.toDomain
import io.github.nikolaiht.forsinket.app.json.toStored
import io.github.nikolaiht.forsinket.domain.Calculation
import io.github.nikolaiht.forsinket.domain.ClaimDetails
import io.github.nikolaiht.forsinket.domain.ClaimEvent
import io.github.nikolaiht.forsinket.domain.ExpenseAssessment
import io.github.nikolaiht.forsinket.domain.ExpenseKind
import io.github.nikolaiht.forsinket.domain.Expenses
import io.github.nikolaiht.forsinket.domain.IneligibilityReason
import io.github.nikolaiht.forsinket.domain.Money
import io.github.nikolaiht.forsinket.domain.Outcome
import io.github.nikolaiht.forsinket.domain.RejectionReason
import io.github.nikolaiht.forsinket.domain.ReviewReason
import io.github.nikolaiht.forsinket.domain.Ticket
import io.github.nikolaiht.forsinket.domain.TicketValue
import io.github.nikolaiht.forsinket.domain.Validity
import io.github.nikolaiht.forsinket.domain.note
import io.github.nikolaiht.forsinket.domain.officerId
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import java.time.Instant

/**
 * The format events are stored in, pinned by files. A round trip through the
 * same code cannot notice a renamed field or enum constant, because both
 * directions change together. These files do not change with the code, so a
 * rename that would make rows already in a database unreadable fails here.
 */
class StoredEventFormatTest : FunSpec({
    fun stored(name: String): String =
        checkNotNull(javaClass.getResource("/stored-events/$name")) { "no such file: $name" }.readText()

    val calculationA = Calculation(
        "v1",
        TicketValue.FullPrice(Money.ofOre(34900)),
        Outcome.Ran(61),
        50,
        Money.ofOre(17450),
        ExpenseAssessment.NoneClaimed,
    )
    val calculationB = Calculation(
        "v1",
        TicketValue.PerDay(Money.ofOre(84900), 30, Money.ofOre(2830)),
        Outcome.Cancelled,
        100,
        Money.ofOre(2830),
        ExpenseAssessment.PendingReview(Money.ofOre(62000), Money.ofOre(62000)),
    )
    val claimB = ClaimDetails(
        ContractFixtures.claimB.departure,
        Ticket.Period(Money.ofOre(84900), Validity.THIRTY_DAYS),
        Expenses(Money.ofOre(62000), ExpenseKind.TAXI),
    )

    val events: List<Pair<String, ClaimEvent>> = listOf(
        "submitted.json" to ClaimEvent.Submitted(claimB, Instant.parse("2026-11-21T10:00:00Z")),
        "approved-automatically.json" to
            ClaimEvent.ApprovedAutomatically(calculationA, Instant.parse("2026-11-21T09:15:00Z")),
        "rejected-automatically.json" to
            ClaimEvent.RejectedAutomatically(IneligibilityReason.SUBMITTED_TOO_LATE, Instant.parse("2027-03-01T08:00:00Z")),
        "sent-to-review.json" to
            ClaimEvent.SentToReview(
                calculationB,
                nonEmptyListOf(ReviewReason.EXPENSES_CLAIMED, ReviewReason.ABOVE_AUTO_APPROVAL_LIMIT),
                Instant.parse("2026-11-21T10:00:00Z"),
            ),
        "approved-by-officer.json" to
            ClaimEvent.ApprovedByOfficer(
                officerId("KN"),
                Money.ofOre(50000),
                note("Kvitteringen viser 500 kr."),
                Instant.parse("2026-11-21T12:30:00.250Z"),
            ),
        "rejected-by-officer.json" to
            ClaimEvent.RejectedByOfficer(
                officerId("KN"),
                RejectionReason.INVALID_TICKET,
                note("Billetten gjaldt en annen dag."),
                Instant.parse("2026-11-21T12:30:00Z"),
            ),
        "payout-recorded.json" to ClaimEvent.PayoutRecorded(Instant.parse("2026-11-22T08:00:00Z")),
    )

    events.forEach { (file, event) ->
        test("$file is read as the event it records") {
            StoredJson.decodeFromString(StoredEvent.serializer(), stored(file)).toDomain() shouldBe event
        }

        test("$file is what that event is written as") {
            StoredJson.encodeToJsonElement(StoredEvent.serializer(), event.toStored()) shouldBe
                StoredJson.parseToJsonElement(stored(file))
        }
    }

    test("every kind of event has a file") {
        events.map { (_, event) -> event::class }.toSet() shouldBe ClaimEvent::class.sealedSubclasses.toSet()
    }

    test("a field added by a later version does not make an old reader fail") {
        val withMore = stored("payout-recorded.json").replace("}", """, "paidBy": "bank"}""")

        StoredJson.decodeFromString(StoredEvent.serializer(), withMore).toDomain() shouldBe
            ClaimEvent.PayoutRecorded(Instant.parse("2026-11-22T08:00:00Z"))
    }
})
