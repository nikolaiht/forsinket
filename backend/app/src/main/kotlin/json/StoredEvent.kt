package io.github.nikolaiht.forsinket.app.json

import arrow.core.getOrElse
import arrow.core.toNonEmptyListOrNull
import io.github.nikolaiht.forsinket.domain.ClaimDetails
import io.github.nikolaiht.forsinket.domain.ClaimEvent
import io.github.nikolaiht.forsinket.domain.IneligibilityReason
import io.github.nikolaiht.forsinket.domain.Money
import io.github.nikolaiht.forsinket.domain.Note
import io.github.nikolaiht.forsinket.domain.OfficerId
import io.github.nikolaiht.forsinket.domain.RejectionReason
import io.github.nikolaiht.forsinket.domain.ReviewReason
import io.github.nikolaiht.forsinket.domain.wireName
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant

/**
 * An event as it is stored: the payload of one row in `claim_events`. The
 * shapes of the values inside (ticket, departure, calculation) are shared with
 * the API. The event shapes themselves are separate from the API's history
 * entries, which show less.
 */
@Serializable
sealed interface StoredEvent {
    val at: String

    @Serializable
    @SerialName("submitted")
    data class Submitted(val claim: StoredClaimDetails, override val at: String) : StoredEvent

    @Serializable
    @SerialName("approved_automatically")
    data class ApprovedAutomatically(val calculation: CalculationDto, override val at: String) : StoredEvent

    @Serializable
    @SerialName("rejected_automatically")
    data class RejectedAutomatically(val reason: String, override val at: String) : StoredEvent

    @Serializable
    @SerialName("sent_to_review")
    data class SentToReview(
        val calculation: CalculationDto,
        val reasons: List<String>,
        override val at: String,
    ) : StoredEvent

    @Serializable
    @SerialName("approved_by_officer")
    data class ApprovedByOfficer(
        val officer: String,
        val approvedExpenses: Long,
        val note: String,
        override val at: String,
    ) : StoredEvent

    @Serializable
    @SerialName("rejected_by_officer")
    data class RejectedByOfficer(
        val officer: String,
        val reason: String,
        val note: String,
        override val at: String,
    ) : StoredEvent

    @Serializable
    @SerialName("payout_recorded")
    data class PayoutRecorded(override val at: String) : StoredEvent
}

@Serializable
data class StoredClaimDetails(
    val departure: DepartureDto,
    val ticket: TicketDto,
    val expenses: ExpensesDto?,
)

fun ClaimEvent.toStored(): StoredEvent =
    when (this) {
        is ClaimEvent.Submitted ->
            StoredEvent.Submitted(
                StoredClaimDetails(claim.departure.toDto(), claim.ticket.toDto(), claim.expenses?.toDto()),
                at.toString(),
            )

        is ClaimEvent.ApprovedAutomatically ->
            StoredEvent.ApprovedAutomatically(calculation.toDto(), at.toString())

        is ClaimEvent.RejectedAutomatically ->
            StoredEvent.RejectedAutomatically(reason.wireName, at.toString())

        is ClaimEvent.SentToReview ->
            StoredEvent.SentToReview(calculation.toDto(), reasons.map { it.wireName }, at.toString())

        is ClaimEvent.ApprovedByOfficer ->
            StoredEvent.ApprovedByOfficer(officer.value, approvedExpenses.ore, note.value, at.toString())

        is ClaimEvent.RejectedByOfficer ->
            StoredEvent.RejectedByOfficer(officer.value, reason.wireName, note.value, at.toString())

        is ClaimEvent.PayoutRecorded ->
            StoredEvent.PayoutRecorded(at.toString())
    }

fun StoredEvent.toDomain(): ClaimEvent {
    val at = Instant.parse(at)
    return when (this) {
        is StoredEvent.Submitted ->
            ClaimEvent.Submitted(
                ClaimDetails(claim.departure.toDomain(), claim.ticket.toDomain(), claim.expenses?.toDomain()),
                at,
            )

        is StoredEvent.ApprovedAutomatically ->
            ClaimEvent.ApprovedAutomatically(calculation.toDomain(), at)

        is StoredEvent.RejectedAutomatically ->
            ClaimEvent.RejectedAutomatically(storedEnum<IneligibilityReason>(reason), at)

        is StoredEvent.SentToReview ->
            ClaimEvent.SentToReview(
                calculation.toDomain(),
                reasons.map { storedEnum<ReviewReason>(it) }.toNonEmptyListOrNull()
                    ?: error("corrupt stored data: a claim was sent to review without a reason"),
                at,
            )

        is StoredEvent.ApprovedByOfficer ->
            ClaimEvent.ApprovedByOfficer(storedOfficer(officer), Money.ofOre(approvedExpenses), storedNote(note), at)

        is StoredEvent.RejectedByOfficer ->
            ClaimEvent.RejectedByOfficer(
                storedOfficer(officer),
                storedEnum<RejectionReason>(reason),
                storedNote(note),
                at,
            )

        is StoredEvent.PayoutRecorded ->
            ClaimEvent.PayoutRecorded(at)
    }
}

private fun storedOfficer(raw: String): OfficerId =
    OfficerId.parse(raw).getOrElse { error("corrupt stored data: '$raw' is not an officer id") }

private fun storedNote(raw: String): Note =
    Note.parse(raw).getOrElse {
        error("corrupt stored data: a stored note is not a valid note")
    }
