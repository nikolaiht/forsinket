package io.github.nikolaiht.forsinket.domain

import arrow.core.EitherNel
import arrow.core.NonEmptyList
import arrow.core.nel
import arrow.core.raise.Raise
import arrow.core.raise.either
import arrow.core.raise.ensure
import arrow.core.raise.ensureNotNull
import arrow.core.raise.withError
import arrow.core.raise.zipOrAccumulate
import java.time.LocalDateTime

enum class Field {
    DEPARTURE_ID,
    TICKET_PRICE,
    TICKET_VALIDITY_DAYS,
    EXPENSES_AMOUNT,
    EXPENSES_KIND,
    OFFICER,
    NOTE,
    DECISION_REASON,
    APPROVED_EXPENSES,
}

enum class ErrorCode {
    UNKNOWN_DEPARTURE,
    DEPARTURE_IN_FUTURE,
    MUST_BE_POSITIVE,
    MUST_NOT_BE_NEGATIVE,
    ABOVE_MAXIMUM,
    UNSUPPORTED_VALIDITY,
    UNKNOWN_VALUE,
    REQUIRED,
    TOO_LONG,
    INVALID_FORMAT,
}

data class FieldError(val field: Field, val code: ErrorCode)

/** A claim as it arrives: primitives that have been parsed but not yet checked. */
data class ClaimDraft(
    val departureId: String,
    val ticket: TicketDraft,
    val expenses: ExpensesDraft?,
)

sealed interface TicketDraft {
    val priceOre: Long

    data class Single(override val priceOre: Long) : TicketDraft

    data class Period(override val priceOre: Long, val validityDays: Int) : TicketDraft
}

data class ExpensesDraft(val amountOre: Long, val kind: String)

/**
 * Turns a draft into [ClaimDetails], or reports everything that is wrong with
 * it. Errors are collected, not short-circuited: a passenger who got three
 * fields wrong is told about all three at once.
 *
 * [departure] is what the traffic system returned for the draft's departure
 * id, or null when it knows no such departure. The lookup itself is I/O and
 * belongs to the caller. So does reading the clock: [now] is the local time
 * where the trains run.
 */
fun validateClaim(
    rules: RuleSet,
    draft: ClaimDraft,
    departure: Departure?,
    now: LocalDateTime,
): EitherNel<FieldError, ClaimDetails> =
    either {
        zipOrAccumulate(
            { departureThatWasDue(departure, now) },
            { withNel { ticket(rules, draft.ticket) } },
            { draft.expenses?.let { withNel { expenses(rules, it) } } },
        ) { knownDeparture, ticket, expenses ->
            ClaimDetails(knownDeparture, ticket, expenses)
        }
    }

private fun Raise<FieldError>.departureThatWasDue(departure: Departure?, now: LocalDateTime): Departure {
    ensureNotNull(departure) { FieldError(Field.DEPARTURE_ID, ErrorCode.UNKNOWN_DEPARTURE) }
    ensure(departure.wasDueBy(now)) { FieldError(Field.DEPARTURE_ID, ErrorCode.DEPARTURE_IN_FUTURE) }
    return departure
}

// A ticket and the expenses each have fields of their own, so each collects
// its own errors and hands them up as a list.

private fun Raise<NonEmptyList<FieldError>>.ticket(rules: RuleSet, draft: TicketDraft): Ticket =
    when (draft) {
        is TicketDraft.Single ->
            Ticket.Single(
                withError({ it.nel() }) {
                    positiveAmount(Field.TICKET_PRICE, draft.priceOre, max = rules.maxTicketPrice)
                },
            )

        is TicketDraft.Period ->
            zipOrAccumulate(
                { positiveAmount(Field.TICKET_PRICE, draft.priceOre, max = rules.maxTicketPrice) },
                { validity(draft.validityDays) },
            ) { price, validity -> Ticket.Period(price, validity) }
    }

private fun Raise<NonEmptyList<FieldError>>.expenses(rules: RuleSet, draft: ExpensesDraft): Expenses =
    zipOrAccumulate(
        { positiveAmount(Field.EXPENSES_AMOUNT, draft.amountOre, max = rules.maxClaimedExpenses) },
        { enumValue<ExpenseKind>(Field.EXPENSES_KIND, draft.kind) },
    ) { amount, kind -> Expenses(amount, kind) }

private fun Raise<FieldError>.positiveAmount(field: Field, ore: Long, max: Money): Money {
    ensure(ore > 0) { FieldError(field, ErrorCode.MUST_BE_POSITIVE) }
    ensure(ore <= max.ore) { FieldError(field, ErrorCode.ABOVE_MAXIMUM) }
    return Money.ofOre(ore)
}

private fun Raise<FieldError>.validity(days: Int): Validity =
    ensureNotNull(Validity.entries.find { it.days == days }) {
        FieldError(Field.TICKET_VALIDITY_DAYS, ErrorCode.UNSUPPORTED_VALIDITY)
    }

/** Reads an enum from its [code], or raises [ErrorCode.UNKNOWN_VALUE] for [field]. */
internal inline fun <reified E : Enum<E>> Raise<FieldError>.enumValue(field: Field, raw: String): E =
    ensureNotNull(enumValues<E>().find { it.wireName == raw }) {
        FieldError(field, ErrorCode.UNKNOWN_VALUE)
    }
