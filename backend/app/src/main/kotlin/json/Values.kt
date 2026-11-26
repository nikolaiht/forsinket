package io.github.nikolaiht.forsinket.app.json

import io.github.nikolaiht.forsinket.domain.Calculation
import io.github.nikolaiht.forsinket.domain.Departure
import io.github.nikolaiht.forsinket.domain.DepartureId
import io.github.nikolaiht.forsinket.domain.ExpenseAssessment
import io.github.nikolaiht.forsinket.domain.ExpenseKind
import io.github.nikolaiht.forsinket.domain.Expenses
import io.github.nikolaiht.forsinket.domain.ExpensesDraft
import io.github.nikolaiht.forsinket.domain.Money
import io.github.nikolaiht.forsinket.domain.Outcome
import io.github.nikolaiht.forsinket.domain.Ticket
import io.github.nikolaiht.forsinket.domain.TicketDraft
import io.github.nikolaiht.forsinket.domain.TicketValue
import io.github.nikolaiht.forsinket.domain.Validity
import io.github.nikolaiht.forsinket.domain.code
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.time.LocalTime

// The JSON shapes of the values that appear both in the API and in stored
// events. The domain types carry no annotations; every translation between
// the two is a function in this file, in both directions where both are needed.

@Serializable
sealed interface TicketDto {
    @Serializable
    @SerialName("single")
    data class Single(val price: Long) : TicketDto

    @Serializable
    @SerialName("period")
    data class Period(val price: Long, val validityDays: Int) : TicketDto
}

@Serializable
data class ExpensesDto(val amount: Long, val kind: String)

@Serializable
sealed interface OutcomeDto {
    @Serializable
    @SerialName("ran")
    data class Ran(val delayMinutes: Int) : OutcomeDto

    @Serializable
    @SerialName("cancelled")
    data object Cancelled : OutcomeDto
}

@Serializable
data class DepartureDto(
    val id: String,
    val date: String,
    val trainNumber: String,
    val origin: String,
    val destination: String,
    val scheduledDeparture: String,
    val outcome: OutcomeDto,
)

@Serializable
sealed interface TicketValueDto {
    @Serializable
    @SerialName("full_price")
    data class FullPrice(val value: Long) : TicketValueDto

    @Serializable
    @SerialName("per_day")
    data class PerDay(val price: Long, val days: Int, val value: Long) : TicketValueDto
}

@Serializable
sealed interface ExpenseAssessmentDto {
    @Serializable
    @SerialName("none_claimed")
    data object NoneClaimed : ExpenseAssessmentDto

    @Serializable
    @SerialName("not_covered")
    data class NotCovered(val claimed: Long) : ExpenseAssessmentDto

    @Serializable
    @SerialName("pending_review")
    data class PendingReview(val claimed: Long, val maxCoverable: Long) : ExpenseAssessmentDto

    @Serializable
    @SerialName("covered")
    data class Covered(val claimed: Long, val approved: Long) : ExpenseAssessmentDto
}

/** [total] is written for the reader's convenience. It is never read back: the domain computes it. */
@Serializable
data class CalculationDto(
    val ruleSetVersion: String,
    val ticketValue: TicketValueDto,
    val outcome: OutcomeDto,
    val percent: Int,
    val ticketCompensation: Long,
    val expenses: ExpenseAssessmentDto,
    val total: Long,
)

// Domain to JSON.

fun Ticket.toDto(): TicketDto =
    when (this) {
        is Ticket.Single -> TicketDto.Single(price.ore)
        is Ticket.Period -> TicketDto.Period(price.ore, validity.days)
    }

fun Expenses.toDto(): ExpensesDto =
    ExpensesDto(amount.ore, kind.code)

fun Outcome.toDto(): OutcomeDto =
    when (this) {
        is Outcome.Ran -> OutcomeDto.Ran(delayMinutes)
        Outcome.Cancelled -> OutcomeDto.Cancelled
    }

fun Departure.toDto(): DepartureDto =
    DepartureDto(
        id = id.value,
        date = date.toString(),
        trainNumber = trainNumber,
        origin = origin,
        destination = destination,
        scheduledDeparture = scheduledDeparture.toString(),
        outcome = outcome.toDto(),
    )

fun TicketValue.toDto(): TicketValueDto =
    when (this) {
        is TicketValue.FullPrice -> TicketValueDto.FullPrice(value.ore)
        is TicketValue.PerDay -> TicketValueDto.PerDay(price.ore, days, value.ore)
    }

fun ExpenseAssessment.toDto(): ExpenseAssessmentDto =
    when (this) {
        ExpenseAssessment.NoneClaimed -> ExpenseAssessmentDto.NoneClaimed
        is ExpenseAssessment.NotCovered -> ExpenseAssessmentDto.NotCovered(claimed.ore)
        is ExpenseAssessment.PendingReview -> ExpenseAssessmentDto.PendingReview(claimed.ore, maxCoverable.ore)
        is ExpenseAssessment.Covered -> ExpenseAssessmentDto.Covered(claimed.ore, approved.ore)
    }

fun Calculation.toDto(): CalculationDto =
    CalculationDto(
        ruleSetVersion = ruleSetVersion,
        ticketValue = ticketValue.toDto(),
        outcome = outcome.toDto(),
        percent = percent,
        ticketCompensation = ticketCompensation.ore,
        expenses = expenses.toDto(),
        total = total.ore,
    )

// A request to a draft. Nothing is checked here: the domain validates drafts.

fun TicketDto.toDraft(): TicketDraft =
    when (this) {
        is TicketDto.Single -> TicketDraft.Single(price)
        is TicketDto.Period -> TicketDraft.Period(price, validityDays)
    }

fun ExpensesDto.toDraft(): ExpensesDraft =
    ExpensesDraft(amount, kind)

// Stored JSON back to the domain. This is data the service wrote itself, so
// anything it cannot read is corruption and fails loudly.

fun TicketDto.toDomain(): Ticket =
    when (this) {
        is TicketDto.Single ->
            Ticket.Single(Money.ofOre(price))

        is TicketDto.Period ->
            Ticket.Period(
                Money.ofOre(price),
                Validity.entries.find { it.days == validityDays }
                    ?: error("corrupt stored data: no ticket is valid for $validityDays days"),
            )
    }

fun ExpensesDto.toDomain(): Expenses =
    Expenses(Money.ofOre(amount), storedEnum<ExpenseKind>(kind))

fun OutcomeDto.toDomain(): Outcome =
    when (this) {
        is OutcomeDto.Ran -> Outcome.Ran(delayMinutes)
        OutcomeDto.Cancelled -> Outcome.Cancelled
    }

fun DepartureDto.toDomain(): Departure =
    Departure(
        id = DepartureId(id),
        date = LocalDate.parse(date),
        trainNumber = trainNumber,
        origin = origin,
        destination = destination,
        scheduledDeparture = LocalTime.parse(scheduledDeparture),
        outcome = outcome.toDomain(),
    )

fun TicketValueDto.toDomain(): TicketValue =
    when (this) {
        is TicketValueDto.FullPrice -> TicketValue.FullPrice(Money.ofOre(value))
        is TicketValueDto.PerDay -> TicketValue.PerDay(Money.ofOre(price), days, Money.ofOre(value))
    }

fun ExpenseAssessmentDto.toDomain(): ExpenseAssessment =
    when (this) {
        ExpenseAssessmentDto.NoneClaimed ->
            ExpenseAssessment.NoneClaimed

        is ExpenseAssessmentDto.NotCovered ->
            ExpenseAssessment.NotCovered(Money.ofOre(claimed))

        is ExpenseAssessmentDto.PendingReview ->
            ExpenseAssessment.PendingReview(Money.ofOre(claimed), Money.ofOre(maxCoverable))

        is ExpenseAssessmentDto.Covered ->
            ExpenseAssessment.Covered(Money.ofOre(claimed), Money.ofOre(approved))
    }

fun CalculationDto.toDomain(): Calculation =
    Calculation(
        ruleSetVersion = ruleSetVersion,
        ticketValue = ticketValue.toDomain(),
        outcome = outcome.toDomain(),
        percent = percent,
        ticketCompensation = Money.ofOre(ticketCompensation),
        expenses = expenses.toDomain(),
    )
