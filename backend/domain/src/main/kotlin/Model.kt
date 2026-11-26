package io.github.nikolaiht.forsinket.domain

import java.time.LocalDate
import java.time.LocalDateTime
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
) {
    /**
     * Whether the departure was due to leave at or before [now], in the local
     * time the timetable is written in. Until then there is nothing to claim
     * for: a train cannot be late before it was meant to go.
     */
    fun wasDueBy(now: LocalDateTime): Boolean = !date.atTime(scheduledDeparture).isAfter(now)
}

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
 * The name an enum value goes by outside the program, in the API and in stored
 * events: the constant's name in lower case. Validation reads values this way,
 * and the JSON layer writes them this way. Renaming a constant therefore
 * changes the API and the stored data, which `WireNamesTest` is there to catch.
 */
val Enum<*>.wireName: String
    get() = name.lowercase()
