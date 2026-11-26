package io.github.nikolaiht.forsinket.domain

import arrow.core.left
import arrow.core.nonEmptyListOf
import arrow.core.right
import io.github.nikolaiht.forsinket.domain.ClaimCommand.Decide
import io.github.nikolaiht.forsinket.domain.ClaimCommand.RecordPayout
import io.github.nikolaiht.forsinket.domain.ClaimCommand.Submit
import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import java.time.Instant

class DeciderTest : FunSpec({
    val submittedAt = Instant.parse("2026-11-21T09:15:00Z")
    val decidedAt = Instant.parse("2026-11-21T12:30:00Z")
    val paidAt = Instant.parse("2026-11-22T08:00:00Z")

    val kn = officerId("KN")
    val receiptNote = note("Kvitteringen viser 500 kr.")

    // The three hand-written examples the contract uses.
    val claimA = ClaimDetails(departure(61), Ticket.Single(Money.ofKroner(349)), expenses = null)
    val claimB = ClaimDetails(
        departure(130),
        Ticket.Period(Money.ofKroner(849), Validity.THIRTY_DAYS),
        Expenses(Money.ofKroner(620), ExpenseKind.TAXI),
    )
    val claimC = ClaimDetails(departure(29), Ticket.Single(Money.ofKroner(349)), expenses = null)

    val calculationA = Calculation(
        "v1",
        TicketValue.FullPrice(Money.ofKroner(349)),
        Outcome.Ran(61),
        50,
        Money.ofOre(17450),
        ExpenseAssessment.NoneClaimed,
    )
    val calculationB = Calculation(
        "v1",
        TicketValue.PerDay(Money.ofKroner(849), 30, Money.ofOre(2830)),
        Outcome.Ran(130),
        100,
        Money.ofOre(2830),
        ExpenseAssessment.PendingReview(claimed = Money.ofOre(62000), maxCoverable = Money.ofOre(62000)),
    )

    fun decide(state: ClaimState, command: ClaimCommand) = decide(RulesV1, state, command)

    /** The state after a command that must be accepted. */
    fun ClaimState.after(command: ClaimCommand): ClaimState =
        decide(this, command).fold(
            ifLeft = { error("$command was rejected with $it") },
            ifRight = { events -> events.fold(this, ::evolve) },
        )

    fun approve(ore: Long) = Decide(OfficerDecision.Approve(Money.ofOre(ore)), kn, receiptNote, decidedAt)
    val reject = Decide(OfficerDecision.Reject(RejectionReason.DUPLICATE_CLAIM), kn, receiptNote, decidedAt)

    val awaitingReview = ClaimState.NotSubmitted.after(Submit(claimB, submittedAt))
    val approved = ClaimState.NotSubmitted.after(Submit(claimA, submittedAt))
    val rejected = ClaimState.NotSubmitted.after(Submit(claimC, submittedAt))
    val paidOut = approved.after(RecordPayout(paidAt))

    context("submitting") {
        test("a claim the rules can settle is received and approved in one go") {
            decide(ClaimState.NotSubmitted, Submit(claimA, submittedAt)) shouldBe
                nonEmptyListOf(
                    ClaimEvent.Submitted(claimA, submittedAt),
                    ClaimEvent.ApprovedAutomatically(calculationA, submittedAt),
                ).right()

            approved shouldBe
                ClaimState.Approved(claimA, submittedAt, calculationA, DecidedBy.Rules, decidedAt = submittedAt)
        }

        test("a claim with expenses is received and sent to an officer") {
            decide(ClaimState.NotSubmitted, Submit(claimB, submittedAt)) shouldBe
                nonEmptyListOf(
                    ClaimEvent.Submitted(claimB, submittedAt),
                    ClaimEvent.SentToReview(calculationB, nonEmptyListOf(ReviewReason.EXPENSES_CLAIMED), submittedAt),
                ).right()

            awaitingReview shouldBe
                ClaimState.AwaitingReview(
                    claimB,
                    submittedAt,
                    calculationB,
                    nonEmptyListOf(ReviewReason.EXPENSES_CLAIMED),
                )
        }

        test("a claim the rules turn down is received and rejected in one go") {
            decide(ClaimState.NotSubmitted, Submit(claimC, submittedAt)) shouldBe
                nonEmptyListOf(
                    ClaimEvent.Submitted(claimC, submittedAt),
                    ClaimEvent.RejectedAutomatically(IneligibilityReason.DELAY_BELOW_THRESHOLD, submittedAt),
                ).right()

            rejected shouldBe
                ClaimState.Rejected(
                    claimC,
                    submittedAt,
                    Rejection.ByRules(IneligibilityReason.DELAY_BELOW_THRESHOLD),
                    decidedAt = submittedAt,
                )
        }

        test("the deadline is counted in Oslo dates, not UTC dates") {
            // 23:30 UTC on day 90 is already day 91 in Oslo.
            val lateEvening = Instant.parse("2027-02-18T23:30:00Z")

            decide(ClaimState.NotSubmitted, Submit(claimA, lateEvening)) shouldBe
                nonEmptyListOf(
                    ClaimEvent.Submitted(claimA, lateEvening),
                    ClaimEvent.RejectedAutomatically(IneligibilityReason.SUBMITTED_TOO_LATE, lateEvening),
                ).right()
        }

        test("a claim cannot be submitted twice") {
            listOf(awaitingReview, approved, rejected, paidOut).forEach { state ->
                decide(state, Submit(claimA, submittedAt)) shouldBe
                    ClaimError.InvalidTransition((state as ClaimState.Filed).status).left()
            }
        }
    }

    context("an officer's decision") {
        test("approving sets the covered expenses, and the total follows") {
            decide(awaitingReview, approve(50000)) shouldBe
                nonEmptyListOf(ClaimEvent.ApprovedByOfficer(kn, Money.ofOre(50000), receiptNote, decidedAt)).right()

            val state = awaitingReview.after(approve(50000))

            state shouldBe
                ClaimState.Approved(
                    claimB,
                    submittedAt,
                    calculationB.copy(
                        expenses = ExpenseAssessment.Covered(
                            claimed = Money.ofOre(62000),
                            approved = Money.ofOre(50000),
                        ),
                    ),
                    DecidedBy.Officer(kn, receiptNote),
                    decidedAt,
                )
            (state as ClaimState.Approved).calculation.total shouldBe Money.ofOre(52830)
        }

        test("the officer may cover everything that was claimed, up to the cap") {
            decide(awaitingReview, approve(62000)).shouldBeRight()
        }

        test("the officer cannot cover more than the rules allow") {
            decide(awaitingReview, approve(62001)) shouldBe
                ClaimError.ApprovedExpensesAboveLimit(Money.ofOre(62000)).left()
        }

        test("with no expenses up for review, nothing can be covered") {
            val expensive = ClaimDetails(cancelledDeparture(), Ticket.Single(Money.ofKroner(2500)), expenses = null)
            val overTheLimit = ClaimState.NotSubmitted.after(Submit(expensive, submittedAt))

            decide(overTheLimit, approve(1)) shouldBe ClaimError.ApprovedExpensesAboveLimit(Money.ZERO).left()
            decide(overTheLimit, approve(0)).shouldBeRight()
        }

        test("rejecting records the reason and who decided") {
            awaitingReview.after(reject) shouldBe
                ClaimState.Rejected(
                    claimB,
                    submittedAt,
                    Rejection.ByOfficer(RejectionReason.DUPLICATE_CLAIM, kn, receiptNote),
                    decidedAt,
                )
        }

        test("only a claim awaiting review can be decided") {
            decide(approved, approve(0)) shouldBe ClaimError.InvalidTransition(StatusName.APPROVED).left()
            decide(rejected, approve(0)) shouldBe ClaimError.InvalidTransition(StatusName.REJECTED).left()
            decide(paidOut, reject) shouldBe ClaimError.InvalidTransition(StatusName.PAID_OUT).left()
        }
    }

    context("payout") {
        test("an approved claim can be paid out, and keeps who approved it") {
            decide(approved, RecordPayout(paidAt)) shouldBe nonEmptyListOf(ClaimEvent.PayoutRecorded(paidAt)).right()

            paidOut shouldBe
                ClaimState.PaidOut(claimA, submittedAt, calculationA, DecidedBy.Rules, decidedAt = submittedAt, paidAt)
        }

        test("nothing else can be paid out") {
            decide(awaitingReview, RecordPayout(paidAt)) shouldBe
                ClaimError.InvalidTransition(StatusName.AWAITING_REVIEW).left()
            decide(rejected, RecordPayout(paidAt)) shouldBe ClaimError.InvalidTransition(StatusName.REJECTED).left()
            decide(paidOut, RecordPayout(paidAt)) shouldBe ClaimError.InvalidTransition(StatusName.PAID_OUT).left()
        }
    }

    context("a claim that does not exist") {
        test("can only be submitted") {
            decide(ClaimState.NotSubmitted, approve(0)) shouldBe ClaimError.NotSubmitted.left()
            decide(ClaimState.NotSubmitted, RecordPayout(paidAt)) shouldBe ClaimError.NotSubmitted.left()
        }
    }

    context("replaying events") {
        test("rebuilds the state from nothing") {
            val events = listOf(
                ClaimEvent.Submitted(claimA, submittedAt),
                ClaimEvent.ApprovedAutomatically(calculationA, submittedAt),
                ClaimEvent.PayoutRecorded(paidAt),
            )

            replay(events) shouldBe paidOut
            replay(emptyList()) shouldBe ClaimState.NotSubmitted
        }

        test("an approval that covers expenses nobody claimed is corrupt too") {
            val expensive = ClaimDetails(cancelledDeparture(), Ticket.Single(Money.ofKroner(2500)), expenses = null)
            val overTheLimit = ClaimState.NotSubmitted.after(Submit(expensive, submittedAt))

            shouldThrow<IllegalStateException> {
                evolve(overTheLimit, ClaimEvent.ApprovedByOfficer(kn, Money.ofOre(1), receiptNote, decidedAt))
            }
        }

        test("a stream that decide could not have produced is corrupt, and fails loudly") {
            shouldThrow<IllegalStateException> {
                replay(listOf(ClaimEvent.PayoutRecorded(paidAt)))
            }
            shouldThrow<IllegalStateException> {
                replay(listOf(ClaimEvent.Submitted(claimA, submittedAt), ClaimEvent.Submitted(claimA, submittedAt)))
            }
        }
    }
})
