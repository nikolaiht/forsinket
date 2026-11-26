package io.github.nikolaiht.forsinket.domain

import arrow.core.nonEmptyListOf
import io.github.nikolaiht.forsinket.domain.ReviewReason.ABOVE_AUTO_APPROVAL_LIMIT
import io.github.nikolaiht.forsinket.domain.ReviewReason.EXPENSES_CLAIMED
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe

class AssessTest : FunSpec({
    val single349 = Ticket.Single(Money.ofKroner(349))
    val submitted = exampleDate.plusDays(1)
    val taxi620 = Expenses(Money.ofKroner(620), ExpenseKind.TAXI)

    fun assess(departure: Departure, ticket: Ticket = single349, expenses: Expenses? = null) =
        assess(RulesV1, ClaimDetails(departure, ticket, expenses), submitted)

    fun eligible(
        ticketValue: TicketValue,
        outcome: Outcome,
        percent: Int,
        ticketCompensation: Long,
        expenses: ExpenseAssessment = ExpenseAssessment.NoneClaimed,
        handling: Handling = Handling.AutoApprove,
    ) = Assessment.Eligible(
        Calculation("v1", ticketValue, outcome, percent, Money.ofOre(ticketCompensation), expenses),
        handling,
    )

    val fullPrice349 = TicketValue.FullPrice(Money.ofKroner(349))

    context("the delay decides the percentage of a 349 kr single ticket") {
        listOf(
            Triple(30, 25, 8725L),
            Triple(59, 25, 8725L),
            Triple(60, 50, 17450L),
            Triple(119, 50, 17450L),
            Triple(120, 100, 34900L),
            Triple(300, 100, 34900L),
        ).forEach { (minutes, percent, compensation) ->
            test("$minutes minutes gives $percent %") {
                assess(departure(minutes)) shouldBe
                    eligible(fullPrice349, Outcome.Ran(minutes), percent, compensation)
            }
        }
    }

    test("under 30 minutes gives nothing") {
        assess(departure(29)) shouldBe Assessment.NotEligible(IneligibilityReason.DELAY_BELOW_THRESHOLD)
        assess(departure(0)) shouldBe Assessment.NotEligible(IneligibilityReason.DELAY_BELOW_THRESHOLD)
    }

    test("a cancelled departure gives the full ticket value") {
        assess(cancelledDeparture()) shouldBe eligible(fullPrice349, Outcome.Cancelled, 100, 34900)
    }

    test("a period ticket is worth its price divided by its days") {
        val thirtyDays = Ticket.Period(Money.ofKroner(849), Validity.THIRTY_DAYS)

        assess(departure(130), thirtyDays) shouldBe
            eligible(TicketValue.PerDay(Money.ofKroner(849), 30, Money.ofOre(2830)), Outcome.Ran(130), 100, 2830)
    }

    test("each step rounds, and the next step uses the rounded amount") {
        val sevenDays = Ticket.Period(Money.ofKroner(100), Validity.SEVEN_DAYS)

        // 100 kr / 7 = 14,2857 → 14,29 kr. Half of 14,29 kr = 7,145 → 7,15 kr.
        assess(departure(60), sevenDays) shouldBe
            eligible(TicketValue.PerDay(Money.ofKroner(100), 7, Money.ofOre(1429)), Outcome.Ran(60), 50, 715)
    }

    test("the total is the ticket compensation plus covered expenses") {
        val calculation = Calculation(
            "v1",
            fullPrice349,
            Outcome.Ran(130),
            100,
            Money.ofOre(34900),
            ExpenseAssessment.Covered(claimed = Money.ofOre(62000), approved = Money.ofOre(50000)),
        )

        calculation.total shouldBe Money.ofOre(84900)
    }

    context("expenses") {
        test("under 60 minutes they are not covered, and nothing needs review") {
            val expenses = Expenses(Money.ofKroner(300), ExpenseKind.BUS)

            assess(departure(45), expenses = expenses) shouldBe
                eligible(
                    fullPrice349,
                    Outcome.Ran(45),
                    25,
                    8725,
                    ExpenseAssessment.NotCovered(Money.ofKroner(300)),
                    Handling.AutoApprove,
                )
        }

        test("from 60 minutes they go to an officer, and count for nothing until decided") {
            val assessment = assess(departure(130), expenses = taxi620)

            assessment shouldBe
                eligible(
                    fullPrice349,
                    Outcome.Ran(130),
                    100,
                    34900,
                    ExpenseAssessment.PendingReview(claimed = Money.ofKroner(620), maxCoverable = Money.ofKroner(620)),
                    Handling.ManualReview(nonEmptyListOf(EXPENSES_CLAIMED)),
                )
            (assessment as Assessment.Eligible).calculation.total shouldBe Money.ofOre(34900)
        }

        test("a cancelled departure counts as 60 minutes or more") {
            val assessment = assess(cancelledDeparture(), expenses = taxi620) as Assessment.Eligible

            assessment.calculation.expenses shouldBe
                ExpenseAssessment.PendingReview(claimed = Money.ofKroner(620), maxCoverable = Money.ofKroner(620))
        }

        test("at most 800 kr can be covered") {
            val expenses = Expenses(Money.ofKroner(950), ExpenseKind.TAXI)
            val assessment = assess(departure(60), expenses = expenses) as Assessment.Eligible

            assessment.calculation.expenses shouldBe
                ExpenseAssessment.PendingReview(claimed = Money.ofKroner(950), maxCoverable = Money.ofKroner(800))
        }
    }

    context("automatic approval") {
        val single2500 = Ticket.Single(Money.ofKroner(2500))

        test("exactly 1 000 kr is still approved automatically") {
            val assessment = assess(cancelledDeparture(), Ticket.Single(Money.ofKroner(1000))) as Assessment.Eligible

            assessment.handling shouldBe Handling.AutoApprove
        }

        test("above 1 000 kr goes to an officer") {
            val assessment = assess(cancelledDeparture(), Ticket.Single(Money.ofOre(100_001))) as Assessment.Eligible

            assessment.handling shouldBe Handling.ManualReview(nonEmptyListOf(ABOVE_AUTO_APPROVAL_LIMIT))
        }

        test("a claim can have both reasons for review, expenses first") {
            val assessment = assess(cancelledDeparture(), single2500, taxi620) as Assessment.Eligible

            assessment.handling shouldBe
                Handling.ManualReview(nonEmptyListOf(EXPENSES_CLAIMED, ABOVE_AUTO_APPROVAL_LIMIT))
        }
    }

    context("the 90 day deadline") {
        fun assessOn(submittedOn: java.time.LocalDate, delayMinutes: Int = 61) =
            assess(RulesV1, ClaimDetails(departure(delayMinutes), single349, null), submittedOn)

        test("day 90 is in time") {
            (assessOn(exampleDate.plusDays(90)) is Assessment.Eligible) shouldBe true
        }

        test("day 91 is too late") {
            assessOn(exampleDate.plusDays(91)) shouldBe
                Assessment.NotEligible(IneligibilityReason.SUBMITTED_TOO_LATE)
        }

        test("too late is reported before a delay that is too short") {
            assessOn(exampleDate.plusDays(91), delayMinutes = 5) shouldBe
                Assessment.NotEligible(IneligibilityReason.SUBMITTED_TOO_LATE)
        }
    }
})
