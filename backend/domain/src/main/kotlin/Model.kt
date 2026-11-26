package io.github.nikolaiht.forsinket.domain

import java.time.LocalDate
import java.time.LocalTime

sealed interface Ticket {
    val price: Money

    data class Single(override val price: Money) : Ticket

    data class Period(override val price: Money, val validity: Validity) : Ticket
}

enum class Validity(val days: Int) {
    SEVEN_DAYS(7),
    THIRTY_DAYS(30),
}

enum class ExpenseKind { TAXI, BUS, OTHER }

/** What a passenger paid to get there another way. The amount is always positive. */
data class Expenses(val amount: Money, val kind: ExpenseKind)

@JvmInline
value class DepartureId(val value: String)

/** What happened to a departure, as the traffic system recorded it. */
sealed interface Outcome {
    data class Ran(val delayMinutes: Int) : Outcome

    data object Cancelled : Outcome
}

data class Departure(
    val id: DepartureId,
    val date: LocalDate,
    val trainNumber: String,
    val origin: String,
    val destination: String,
    val scheduledDeparture: LocalTime,
    val outcome: Outcome,
)

/**
 * A claim that has passed validation. It carries the departure as it was
 * recorded when the claim was made, so a later correction in the traffic
 * system cannot change a decision that has already been taken.
 */
data class ClaimDetails(
    val departure: Departure,
    val ticket: Ticket,
    val expenses: Expenses?,
)

/**
 * How enum values are written outside the domain: the name in lower case.
 * Validation reads them this way, and the JSON layer writes them this way.
 */
val Enum<*>.code: String
    get() = name.lowercase()
