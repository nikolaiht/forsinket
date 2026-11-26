package io.github.nikolaiht.forsinket.domain

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.comparables.shouldBeGreaterThan
import io.kotest.matchers.comparables.shouldBeLessThanOrEqualTo
import io.kotest.matchers.shouldBe
import io.kotest.matchers.types.shouldNotBeInstanceOf
import io.kotest.property.Arb
import io.kotest.property.arbitrary.int
import io.kotest.property.checkAll

class AssessPropertyTest : FunSpec({
    val submitted = exampleDate.plusDays(1)

    fun assess(claim: ClaimDetails): Assessment = assess(RulesV1, claim, submitted)

    fun ticketCompensation(ticket: Ticket, delayMinutes: Int): Money =
        when (val assessment = assess(ClaimDetails(departure(delayMinutes), ticket, expenses = null))) {
            is Assessment.Eligible -> assessment.calculation.ticketCompensation
            is Assessment.NotEligible -> Money.ZERO
        }

    test("ticket compensation never exceeds the ticket value, which never exceeds the price") {
        checkAll(Arb.claimDetails()) { claim ->
            val assessment = assess(claim)
            if (assessment is Assessment.Eligible) {
                val calculation = assessment.calculation
                calculation.ticketCompensation shouldBeLessThanOrEqualTo calculation.ticketValue.value
                calculation.ticketValue.value shouldBeLessThanOrEqualTo claim.ticket.price
            }
        }
    }

    test("an eligible claim on a ticket of at least 1 kr always pays something") {
        checkAll(Arb.claimDetails()) { claim ->
            val assessment = assess(claim)
            if (assessment is Assessment.Eligible && claim.ticket.price >= Money.ofKroner(1)) {
                assessment.calculation.ticketCompensation shouldBeGreaterThan Money.ZERO
            }
        }
    }

    test("a longer delay never gives a lower ticket compensation") {
        checkAll(Arb.ticket(), Arb.int(0..300), Arb.int(0..300)) { ticket, a, b ->
            ticketCompensation(ticket, minOf(a, b)) shouldBeLessThanOrEqualTo ticketCompensation(ticket, maxOf(a, b))
        }
    }

    test("nothing is paid for expenses before an officer has decided") {
        checkAll(Arb.claimDetails()) { claim ->
            val assessment = assess(claim)
            if (assessment is Assessment.Eligible) {
                assessment.calculation.expenses.covered shouldBe Money.ZERO
                assessment.calculation.total shouldBe assessment.calculation.ticketCompensation
            }
        }
    }

    test("what an officer may cover is never above the claim or the cap") {
        checkAll(Arb.claimDetails()) { claim ->
            val assessment = assess(claim)
            val expenses = (assessment as? Assessment.Eligible)?.calculation?.expenses
            if (expenses is ExpenseAssessment.PendingReview) {
                expenses.maxCoverable shouldBeLessThanOrEqualTo expenses.claimed
                expenses.maxCoverable shouldBeLessThanOrEqualTo RulesV1.expenseCap
            }
        }
    }

    test("automatic approval leaves nothing for an officer to look at") {
        checkAll(Arb.claimDetails()) { claim ->
            val assessment = assess(claim)
            if (assessment is Assessment.Eligible && assessment.handling is Handling.AutoApprove) {
                assessment.calculation.expenses.shouldNotBeInstanceOf<ExpenseAssessment.PendingReview>()
                assessment.calculation.ticketCompensation shouldBeLessThanOrEqualTo RulesV1.autoApprovalLimit
            }
        }
    }
})
