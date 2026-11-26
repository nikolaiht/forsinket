package io.github.nikolaiht.forsinket.app

import io.github.nikolaiht.forsinket.domain.Assessment
import io.github.nikolaiht.forsinket.domain.ClaimDetails
import io.github.nikolaiht.forsinket.domain.Departure
import io.github.nikolaiht.forsinket.domain.DepartureId
import io.github.nikolaiht.forsinket.domain.ExpenseKind
import io.github.nikolaiht.forsinket.domain.Expenses
import io.github.nikolaiht.forsinket.domain.Money
import io.github.nikolaiht.forsinket.domain.Outcome
import io.github.nikolaiht.forsinket.domain.RuleSet
import io.github.nikolaiht.forsinket.domain.Ticket
import io.github.nikolaiht.forsinket.domain.Validity
import io.github.nikolaiht.forsinket.domain.assess
import java.time.LocalDate
import java.time.LocalTime

data class Example(
    val ticket: Ticket,
    val expenses: Expenses?,
    val outcome: Outcome,
    val assessment: Assessment,
)

/**
 * The worked examples on the front page. They are not written down anywhere:
 * each one is run through [assess], the same function that settles real
 * claims, so the page cannot show an answer the rules would not give.
 */
fun examples(rules: RuleSet): List<Example> {
    val single349 = Ticket.Single(Money.ofKroner(349))
    val thirtyDays849 = Ticket.Period(Money.ofKroner(849), Validity.THIRTY_DAYS)
    val taxi620 = Expenses(Money.ofKroner(620), ExpenseKind.TAXI)

    return listOf(
        example(rules, single349, expenses = null, Outcome.Ran(45)),
        example(rules, single349, expenses = null, Outcome.Ran(75)),
        example(rules, thirtyDays849, taxi620, Outcome.Cancelled),
        example(rules, single349, expenses = null, Outcome.Ran(12)),
    )
}

private fun example(rules: RuleSet, ticket: Ticket, expenses: Expenses?, outcome: Outcome): Example {
    val day = LocalDate.of(2026, 1, 5)
    val departure = Departure(
        id = DepartureId("$day-TB13"),
        date = day,
        trainNumber = "TB13",
        origin = "Fjordvik",
        destination = "Storhavn",
        scheduledDeparture = LocalTime.of(9, 12),
        outcome = outcome,
    )
    return Example(
        ticket,
        expenses,
        outcome,
        assess(rules, ClaimDetails(departure, ticket, expenses), submittedOn = day),
    )
}
