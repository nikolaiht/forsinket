package io.github.nikolaiht.forsinket.domain

import io.kotest.property.Arb
import io.kotest.property.arbitrary.bind
import io.kotest.property.arbitrary.choice
import io.kotest.property.arbitrary.constant
import io.kotest.property.arbitrary.enum
import io.kotest.property.arbitrary.int
import io.kotest.property.arbitrary.long
import io.kotest.property.arbitrary.map
import io.kotest.property.arbitrary.orNull
import java.time.LocalDate
import java.time.LocalTime

/** The travel date the hand-written examples use. A Friday. */
val exampleDate: LocalDate = LocalDate.of(2026, 11, 20)

fun departure(outcome: Outcome, date: LocalDate = exampleDate): Departure =
    Departure(
        id = DepartureId("$date-FB16"),
        date = date,
        trainNumber = "FB16",
        origin = "Storhavn",
        destination = "Fjordvik",
        scheduledDeparture = LocalTime.of(16, 42),
        outcome = outcome,
    )

fun departure(delayMinutes: Int, date: LocalDate = exampleDate): Departure =
    departure(Outcome.Ran(delayMinutes), date)

fun cancelledDeparture(date: LocalDate = exampleDate): Departure =
    departure(Outcome.Cancelled, date)

fun Arb.Companion.money(range: LongRange): Arb<Money> =
    Arb.long(range).map(Money::ofOre)

/** Any ticket the validation accepts: a price from 1 øre up to the cap. */
fun Arb.Companion.ticket(): Arb<Ticket> =
    Arb.choice(
        Arb.money(1L..RulesV1.maxTicketPrice.ore).map { Ticket.Single(it) },
        Arb.bind(Arb.money(1L..RulesV1.maxTicketPrice.ore), Arb.enum<Validity>()) { price, validity ->
            Ticket.Period(price, validity)
        },
    )

fun Arb.Companion.outcome(): Arb<Outcome> =
    Arb.choice(
        Arb.int(0..300).map { Outcome.Ran(it) },
        Arb.constant(Outcome.Cancelled),
    )

fun Arb.Companion.expenses(): Arb<Expenses?> =
    Arb.bind(Arb.money(1L..RulesV1.maxClaimedExpenses.ore), Arb.enum<ExpenseKind>()) { amount, kind ->
        Expenses(amount, kind)
    }.orNull(0.5)

fun Arb.Companion.claimDetails(): Arb<ClaimDetails> =
    Arb.bind(Arb.outcome(), Arb.ticket(), Arb.expenses()) { outcome, ticket, expenses ->
        ClaimDetails(departure(outcome), ticket, expenses)
    }
