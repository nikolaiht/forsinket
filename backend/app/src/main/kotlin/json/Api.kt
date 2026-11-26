package io.github.nikolaiht.forsinket.app.json

import io.github.nikolaiht.forsinket.app.ClaimSnapshot
import io.github.nikolaiht.forsinket.app.ClaimSummary
import io.github.nikolaiht.forsinket.app.Example
import io.github.nikolaiht.forsinket.domain.Assessment
import io.github.nikolaiht.forsinket.domain.ClaimDraft
import io.github.nikolaiht.forsinket.domain.ClaimEvent
import io.github.nikolaiht.forsinket.domain.ClaimState
import io.github.nikolaiht.forsinket.domain.DecidedBy
import io.github.nikolaiht.forsinket.domain.DecisionChoiceDraft
import io.github.nikolaiht.forsinket.domain.DecisionDraft
import io.github.nikolaiht.forsinket.domain.Field
import io.github.nikolaiht.forsinket.domain.FieldError
import io.github.nikolaiht.forsinket.domain.Handling
import io.github.nikolaiht.forsinket.domain.Rejection
import io.github.nikolaiht.forsinket.domain.RuleSet
import io.github.nikolaiht.forsinket.domain.wireName
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// What the API sends and receives. `contract/examples` has one example of each.

@Serializable
data class DelayBandDto(val fromMinutes: Int, val percent: Int)

@Serializable
data class RulesDto(
    val version: String,
    val claimDeadlineDays: Int,
    val bands: List<DelayBandDto>,
    val expenseMinDelayMinutes: Int,
    val expenseCap: Long,
    val autoApprovalLimit: Long,
    val maxTicketPrice: Long,
    val maxClaimedExpenses: Long,
)

@Serializable
sealed interface HandlingDto {
    @Serializable
    @SerialName("auto_approve")
    data object AutoApprove : HandlingDto

    @Serializable
    @SerialName("manual_review")
    data class ManualReview(val reasons: List<String>) : HandlingDto
}

@Serializable
sealed interface AssessmentDto {
    @Serializable
    @SerialName("eligible")
    data class Eligible(val calculation: CalculationDto, val handling: HandlingDto) : AssessmentDto

    @Serializable
    @SerialName("not_eligible")
    data class NotEligible(val reason: String) : AssessmentDto
}

@Serializable
sealed interface DecidedByDto {
    @Serializable
    @SerialName("rules")
    data object Rules : DecidedByDto

    @Serializable
    @SerialName("officer")
    data class Officer(val officer: String, val note: String) : DecidedByDto
}

@Serializable
sealed interface RejectionDto {
    @Serializable
    @SerialName("rules")
    data class ByRules(val reason: String) : RejectionDto

    @Serializable
    @SerialName("officer")
    data class ByOfficer(val reason: String, val officer: String, val note: String) : RejectionDto
}

/** Each status carries the data that exists in it, and nothing else. */
@Serializable
sealed interface StatusDto {
    @Serializable
    @SerialName("received")
    data object Received : StatusDto

    @Serializable
    @SerialName("awaiting_review")
    data class AwaitingReview(val calculation: CalculationDto, val reasons: List<String>) : StatusDto

    @Serializable
    @SerialName("approved")
    data class Approved(val calculation: CalculationDto, val by: DecidedByDto, val decidedAt: String) : StatusDto

    @Serializable
    @SerialName("rejected")
    data class Rejected(val rejection: RejectionDto, val decidedAt: String) : StatusDto

    @Serializable
    @SerialName("paid_out")
    data class PaidOut(
        val calculation: CalculationDto,
        val by: DecidedByDto,
        val decidedAt: String,
        val paidAt: String,
    ) : StatusDto
}

@Serializable
sealed interface HistoryEntryDto {
    @Serializable
    @SerialName("submitted")
    data class Submitted(val at: String) : HistoryEntryDto

    @Serializable
    @SerialName("approved_automatically")
    data class ApprovedAutomatically(val at: String) : HistoryEntryDto

    @Serializable
    @SerialName("rejected_automatically")
    data class RejectedAutomatically(val reason: String, val at: String) : HistoryEntryDto

    @Serializable
    @SerialName("sent_to_review")
    data class SentToReview(val reasons: List<String>, val at: String) : HistoryEntryDto

    @Serializable
    @SerialName("approved_by_officer")
    data class ApprovedByOfficer(
        val officer: String,
        val approvedExpenses: Long,
        val note: String,
        val at: String,
    ) : HistoryEntryDto

    @Serializable
    @SerialName("rejected_by_officer")
    data class RejectedByOfficer(
        val officer: String,
        val reason: String,
        val note: String,
        val at: String,
    ) : HistoryEntryDto

    @Serializable
    @SerialName("payout_recorded")
    data class PayoutRecorded(val at: String) : HistoryEntryDto
}

@Serializable
data class ClaimDto(
    val id: String,
    val version: Int,
    val submittedAt: String,
    val departure: DepartureDto,
    val ticket: TicketDto,
    val expenses: ExpensesDto?,
    val status: StatusDto,
    val history: List<HistoryEntryDto>,
)

@Serializable
data class SummaryDto(
    val id: String,
    val version: Int,
    val status: String,
    val submittedAt: String,
    val departureDate: String,
    val trainNumber: String,
    val total: Long?,
)

/** A worked example for the front page: what a passenger had, what happened, and what the rules say. */
@Serializable
data class ExampleDto(
    val ticket: TicketDto,
    val expenses: ExpensesDto?,
    val outcome: OutcomeDto,
    val assessment: AssessmentDto,
)

@Serializable
data class ClaimRequestDto(
    val departureId: String,
    val ticket: TicketDto,
    val expenses: ExpensesDto? = null,
)

@Serializable
sealed interface DecisionChoiceDto {
    @Serializable
    @SerialName("approve")
    data class Approve(val approvedExpenses: Long) : DecisionChoiceDto

    @Serializable
    @SerialName("reject")
    data class Reject(val reason: String) : DecisionChoiceDto
}

@Serializable
data class DecisionRequestDto(
    val expectedVersion: Int,
    val officer: String,
    val note: String,
    val decision: DecisionChoiceDto,
)

@Serializable
data class PayoutRequestDto(val expectedVersion: Int)

@Serializable
data class FieldErrorDto(val field: String, val code: String)

@Serializable
sealed interface ErrorDto {
    @Serializable
    @SerialName("validation")
    data class Validation(val errors: List<FieldErrorDto>) : ErrorDto

    @Serializable
    @SerialName("not_found")
    data object NotFound : ErrorDto

    @Serializable
    @SerialName("version_conflict")
    data class VersionConflict(val currentVersion: Int) : ErrorDto

    @Serializable
    @SerialName("invalid_transition")
    data class InvalidTransition(val status: String) : ErrorDto

    @Serializable
    @SerialName("malformed_request")
    data class MalformedRequest(val detail: String) : ErrorDto

    @Serializable
    @SerialName("demo_limit_reached")
    data object DemoLimitReached : ErrorDto

    @Serializable
    @SerialName("internal_error")
    data object InternalError : ErrorDto

    companion object {
        const val UNREADABLE_BODY = "The request body could not be read as the JSON this endpoint expects."
    }
}

// Domain to JSON.

fun RuleSet.toDto(): RulesDto =
    RulesDto(
        version = version,
        claimDeadlineDays = claimDeadlineDays,
        bands = bands.map { DelayBandDto(it.fromMinutes, it.percent) },
        expenseMinDelayMinutes = expenseMinDelayMinutes,
        expenseCap = expenseCap.ore,
        autoApprovalLimit = autoApprovalLimit.ore,
        maxTicketPrice = maxTicketPrice.ore,
        maxClaimedExpenses = maxClaimedExpenses.ore,
    )

fun Assessment.toDto(): AssessmentDto =
    when (this) {
        is Assessment.Eligible -> AssessmentDto.Eligible(calculation.toDto(), handling.toDto())
        is Assessment.NotEligible -> AssessmentDto.NotEligible(reason.wireName)
    }

private fun Handling.toDto(): HandlingDto =
    when (this) {
        Handling.AutoApprove -> HandlingDto.AutoApprove
        is Handling.ManualReview -> HandlingDto.ManualReview(reasons.map { it.wireName })
    }

fun ClaimSnapshot.toDto(): ClaimDto =
    ClaimDto(
        id = id.value.toString(),
        version = version,
        submittedAt = state.submittedAt.toString(),
        departure = state.claim.departure.toDto(),
        ticket = state.claim.ticket.toDto(),
        expenses = state.claim.expenses?.toDto(),
        status = state.toDto(),
        history = events.map { it.toHistoryEntry() },
    )

private fun ClaimState.Filed.toDto(): StatusDto =
    when (this) {
        is ClaimState.Received ->
            StatusDto.Received

        is ClaimState.AwaitingReview ->
            StatusDto.AwaitingReview(calculation.toDto(), reasons.map { it.wireName })

        is ClaimState.Approved ->
            StatusDto.Approved(calculation.toDto(), by.toDto(), decidedAt.toString())

        is ClaimState.Rejected ->
            StatusDto.Rejected(rejection.toDto(), decidedAt.toString())

        is ClaimState.PaidOut ->
            StatusDto.PaidOut(calculation.toDto(), by.toDto(), decidedAt.toString(), paidAt.toString())
    }

private fun DecidedBy.toDto(): DecidedByDto =
    when (this) {
        DecidedBy.Rules -> DecidedByDto.Rules
        is DecidedBy.Officer -> DecidedByDto.Officer(officer.value, note.value)
    }

private fun Rejection.toDto(): RejectionDto =
    when (this) {
        is Rejection.ByRules -> RejectionDto.ByRules(reason.wireName)
        is Rejection.ByOfficer -> RejectionDto.ByOfficer(reason.wireName, officer.value, note.value)
    }

/** The history shows what happened and when. The amounts are in the status, where they are current. */
private fun ClaimEvent.toHistoryEntry(): HistoryEntryDto =
    when (this) {
        is ClaimEvent.Submitted ->
            HistoryEntryDto.Submitted(at.toString())

        is ClaimEvent.ApprovedAutomatically ->
            HistoryEntryDto.ApprovedAutomatically(at.toString())

        is ClaimEvent.RejectedAutomatically ->
            HistoryEntryDto.RejectedAutomatically(reason.wireName, at.toString())

        is ClaimEvent.SentToReview ->
            HistoryEntryDto.SentToReview(reasons.map { it.wireName }, at.toString())

        is ClaimEvent.ApprovedByOfficer ->
            HistoryEntryDto.ApprovedByOfficer(officer.value, approvedExpenses.ore, note.value, at.toString())

        is ClaimEvent.RejectedByOfficer ->
            HistoryEntryDto.RejectedByOfficer(officer.value, reason.wireName, note.value, at.toString())

        is ClaimEvent.PayoutRecorded ->
            HistoryEntryDto.PayoutRecorded(at.toString())
    }

fun Example.toDto(): ExampleDto =
    ExampleDto(ticket.toDto(), expenses?.toDto(), outcome.toDto(), assessment.toDto())

fun ClaimSummary.toDto(): SummaryDto =
    SummaryDto(
        id = id.value.toString(),
        version = version,
        status = status.wireName,
        submittedAt = submittedAt.toString(),
        departureDate = departureDate.toString(),
        trainNumber = trainNumber,
        total = total?.ore,
    )

fun FieldError.toDto(): FieldErrorDto =
    FieldErrorDto(field.path, code.wireName)

/** Where a field sits in the request body, so a client can show the error next to the right input. */
private val Field.path: String
    get() =
        when (this) {
            Field.DEPARTURE_ID -> "departureId"
            Field.TICKET_PRICE -> "ticket.price"
            Field.TICKET_VALIDITY_DAYS -> "ticket.validityDays"
            Field.EXPENSES_AMOUNT -> "expenses.amount"
            Field.EXPENSES_KIND -> "expenses.kind"
            Field.OFFICER -> "officer"
            Field.NOTE -> "note"
            Field.DECISION_REASON -> "decision.reason"
            Field.APPROVED_EXPENSES -> "decision.approvedExpenses"
        }

// Requests to drafts. Nothing is checked here: the domain validates drafts.

fun ClaimRequestDto.toDraft(): ClaimDraft =
    ClaimDraft(departureId, ticket.toDraft(), expenses?.toDraft())

fun DecisionRequestDto.toDraft(): DecisionDraft =
    DecisionDraft(
        officer = officer,
        note = note,
        decision =
            when (decision) {
                is DecisionChoiceDto.Approve -> DecisionChoiceDraft.Approve(decision.approvedExpenses)
                is DecisionChoiceDto.Reject -> DecisionChoiceDraft.Reject(decision.reason)
            },
    )
