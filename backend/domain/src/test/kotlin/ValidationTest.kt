package io.github.nikolaiht.forsinket.domain

import arrow.core.left
import arrow.core.nonEmptyListOf
import arrow.core.right
import io.github.nikolaiht.forsinket.domain.ErrorCode.ABOVE_MAXIMUM
import io.github.nikolaiht.forsinket.domain.ErrorCode.DEPARTURE_IN_FUTURE
import io.github.nikolaiht.forsinket.domain.ErrorCode.MUST_BE_POSITIVE
import io.github.nikolaiht.forsinket.domain.ErrorCode.UNKNOWN_DEPARTURE
import io.github.nikolaiht.forsinket.domain.ErrorCode.UNKNOWN_VALUE
import io.github.nikolaiht.forsinket.domain.ErrorCode.UNSUPPORTED_VALIDITY
import io.github.nikolaiht.forsinket.domain.Field.DEPARTURE_ID
import io.github.nikolaiht.forsinket.domain.Field.EXPENSES_AMOUNT
import io.github.nikolaiht.forsinket.domain.Field.EXPENSES_KIND
import io.github.nikolaiht.forsinket.domain.Field.TICKET_PRICE
import io.github.nikolaiht.forsinket.domain.Field.TICKET_VALIDITY_DAYS
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import java.time.LocalDateTime

class ValidationTest : FunSpec({
    // Noon, the day after the departure in the fixtures (which leaves at 16:42).
    val now = exampleDate.plusDays(1).atTime(12, 0)
    val today = now.toLocalDate()
    val departure = departure(delayMinutes = 61)
    val single = ClaimDraft(departure.id.value, TicketDraft.Single(34900), expenses = null)

    fun validate(draft: ClaimDraft, found: Departure? = departure, at: LocalDateTime = now) =
        validateClaim(RulesV1, draft, found, at)

    test("a valid draft becomes claim details") {
        validate(single) shouldBe
            ClaimDetails(departure, Ticket.Single(Money.ofOre(34900)), expenses = null).right()
    }

    test("a period ticket with expenses is accepted") {
        val draft = ClaimDraft(departure.id.value, TicketDraft.Period(84900, 30), ExpensesDraft(62000, "taxi"))

        validate(draft) shouldBe
            ClaimDetails(
                departure,
                Ticket.Period(Money.ofOre(84900), Validity.THIRTY_DAYS),
                Expenses(Money.ofOre(62000), ExpenseKind.TAXI),
            ).right()
    }

    test("every problem is reported at once, in field order") {
        val draft = ClaimDraft("nope", TicketDraft.Period(0, 14), ExpensesDraft(100, "boat"))

        validate(draft, found = null) shouldBe
            nonEmptyListOf(
                FieldError(DEPARTURE_ID, UNKNOWN_DEPARTURE),
                FieldError(TICKET_PRICE, MUST_BE_POSITIVE),
                FieldError(TICKET_VALIDITY_DAYS, UNSUPPORTED_VALIDITY),
                FieldError(EXPENSES_KIND, UNKNOWN_VALUE),
            ).left()
    }

    test("a departure after today has not run yet") {
        validate(single, found = departure(delayMinutes = 61, date = today.plusDays(1))) shouldBe
            nonEmptyListOf(FieldError(DEPARTURE_ID, DEPARTURE_IN_FUTURE)).left()
    }

    test("a departure later today has not run yet either") {
        validate(single, found = departure(delayMinutes = 61, date = today)) shouldBe
            nonEmptyListOf(FieldError(DEPARTURE_ID, DEPARTURE_IN_FUTURE)).left()
    }

    test("a departure is claimable from the minute it was due to leave") {
        val leavesToday = departure(delayMinutes = 61, date = today)

        validate(single, found = leavesToday, at = today.atTime(16, 41)).isLeft() shouldBe true
        validate(single, found = leavesToday, at = today.atTime(16, 42)).shouldBeRight()
    }

    test("the ticket price is capped at 20 000 kr") {
        validate(single.copy(ticket = TicketDraft.Single(2_000_000))).shouldBeRight()
        validate(single.copy(ticket = TicketDraft.Single(2_000_001))) shouldBe
            nonEmptyListOf(FieldError(TICKET_PRICE, ABOVE_MAXIMUM)).left()
    }

    test("a negative price is not a price") {
        validate(single.copy(ticket = TicketDraft.Single(-34900))) shouldBe
            nonEmptyListOf(FieldError(TICKET_PRICE, MUST_BE_POSITIVE)).left()
    }

    test("claimed expenses must be positive") {
        validate(single.copy(expenses = ExpensesDraft(0, "bus"))) shouldBe
            nonEmptyListOf(FieldError(EXPENSES_AMOUNT, MUST_BE_POSITIVE)).left()
    }

    test("claimed expenses are capped at 10 000 kr") {
        validate(single.copy(expenses = ExpensesDraft(1_000_000, "other"))).shouldBeRight()
        validate(single.copy(expenses = ExpensesDraft(1_000_001, "other"))) shouldBe
            nonEmptyListOf(FieldError(EXPENSES_AMOUNT, ABOVE_MAXIMUM)).left()
    }
})
