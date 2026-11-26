package io.github.nikolaiht.forsinket.domain

import arrow.core.NonEmptyList
import arrow.core.raise.Raise
import arrow.core.raise.either
import arrow.core.raise.ensure
import arrow.core.raise.ensureNotNull
import arrow.core.toNonEmptyListOrNull
import java.time.LocalDate

/** What the rules say about a claim, before anything is recorded. */
sealed interface Assessment {
    data class NotEligible(val reason: IneligibilityReason) : Assessment

    data class Eligible(val calculation: Calculation, val handling: Handling) : Assessment
}

enum class IneligibilityReason { SUBMITTED_TOO_LATE, DELAY_BELOW_THRESHOLD }

/** Who decides an eligible claim: the rules alone, or an officer. */
sealed interface Handling {
    data object AutoApprove : Handling

    data class ManualReview(val reasons: NonEmptyList<ReviewReason>) : Handling
}

enum class ReviewReason { EXPENSES_CLAIMED, ABOVE_AUTO_APPROVAL_LIMIT }

/**
 * How an amount was arrived at, step by step. Each step holds the amount the
 * next step used, so the calculation can be checked by hand from what is shown.
 */
data class Calculation(
    val ruleSetVersion: String,
    val ticketValue: TicketValue,
    val outcome: Outcome,
    val percent: Int,
    val ticketCompensation: Money,
    val expenses: ExpenseAssessment,
) {
    val total: Money
        get() = ticketCompensation + expenses.covered
}

/** What one journey on the ticket is worth. */
sealed interface TicketValue {
    val value: Money

    data class FullPrice(override val value: Money) : TicketValue

    data class PerDay(val price: Money, val days: Int, override val value: Money) : TicketValue
}

sealed interface ExpenseAssessment {
    /** What is paid for expenses as things stand. */
    val covered: Money

    data object NoneClaimed : ExpenseAssessment {
        override val covered: Money get() = Money.ZERO
    }

    /** Claimed, but the delay was too short to give a right to cover. */
    data class NotCovered(val claimed: Money) : ExpenseAssessment {
        override val covered: Money get() = Money.ZERO
    }

    /** An officer has to look at the receipt. Nothing is covered until then. */
    data class PendingReview(val claimed: Money, val maxCoverable: Money) : ExpenseAssessment {
        override val covered: Money get() = Money.ZERO
    }

    data class Covered(val claimed: Money, val approved: Money) : ExpenseAssessment {
        override val covered: Money get() = approved
    }
}

/**
 * Applies the rules to a claim. Pure: the same rules, claim and date always
 * give the same answer, and the date the claim was submitted is an argument,
 * not something read from a clock.
 */
fun assess(rules: RuleSet, claim: ClaimDetails, submittedOn: LocalDate): Assessment =
    either { calculate(rules, claim, submittedOn) }
        .fold(
            ifLeft = Assessment::NotEligible,
            ifRight = { calculation -> Assessment.Eligible(calculation, handlingOf(rules, calculation)) },
        )

private fun Raise<IneligibilityReason>.calculate(
    rules: RuleSet,
    claim: ClaimDetails,
    submittedOn: LocalDate,
): Calculation {
    val deadline = claim.departure.date.plusDays(rules.claimDeadlineDays.toLong())
    ensure(!submittedOn.isAfter(deadline)) { IneligibilityReason.SUBMITTED_TOO_LATE }

    val outcome = claim.departure.outcome
    val band = ensureNotNull(rules.bandFor(outcome)) { IneligibilityReason.DELAY_BELOW_THRESHOLD }
    val ticketValue = ticketValueOf(claim.ticket)

    return Calculation(
        ruleSetVersion = rules.version,
        ticketValue = ticketValue,
        outcome = outcome,
        percent = band.percent,
        ticketCompensation = ticketValue.value.percent(band.percent),
        expenses = assessExpenses(rules, claim.expenses, outcome),
    )
}

private fun ticketValueOf(ticket: Ticket): TicketValue =
    when (ticket) {
        is Ticket.Single ->
            TicketValue.FullPrice(ticket.price)

        is Ticket.Period ->
            TicketValue.PerDay(
                price = ticket.price,
                days = ticket.validity.days,
                value = ticket.price.dividedBy(ticket.validity.days),
            )
    }

private fun assessExpenses(rules: RuleSet, expenses: Expenses?, outcome: Outcome): ExpenseAssessment =
    when {
        expenses == null ->
            ExpenseAssessment.NoneClaimed

        !rules.coversExpensesFor(outcome) ->
            ExpenseAssessment.NotCovered(expenses.amount)

        else ->
            ExpenseAssessment.PendingReview(
                claimed = expenses.amount,
                maxCoverable = minOf(expenses.amount, rules.expenseCap),
            )
    }

private fun handlingOf(rules: RuleSet, calculation: Calculation): Handling =
    listOfNotNull(
        ReviewReason.EXPENSES_CLAIMED.takeIf { calculation.expenses is ExpenseAssessment.PendingReview },
        ReviewReason.ABOVE_AUTO_APPROVAL_LIMIT.takeIf { calculation.ticketCompensation > rules.autoApprovalLimit },
    )
        .toNonEmptyListOrNull()
        ?.let(Handling::ManualReview)
        ?: Handling.AutoApprove
