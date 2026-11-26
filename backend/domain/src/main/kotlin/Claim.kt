package io.github.nikolaiht.forsinket.domain

import arrow.core.Either
import arrow.core.NonEmptyList
import arrow.core.raise.either
import arrow.core.raise.ensure
import java.time.Instant
import java.util.UUID

@JvmInline
value class ClaimId(val value: UUID)

/** An officer's initials: 2 to 10 letters. */
@JvmInline
value class OfficerId private constructor(val value: String) {
    companion object {
        private val format = Regex("""\p{L}{2,10}""")

        fun parse(raw: String): Either<FieldError, OfficerId> =
            either {
                val trimmed = raw.trim()
                ensure(trimmed.isNotEmpty()) { FieldError(Field.OFFICER, ErrorCode.REQUIRED) }
                ensure(format.matches(trimmed)) { FieldError(Field.OFFICER, ErrorCode.INVALID_FORMAT) }
                OfficerId(trimmed)
            }
    }
}

/**
 * An officer's free-text reasoning. Trimmed, possibly empty, at most
 * [MAX_LENGTH] characters, and made of text: line breaks are fine, other
 * control characters are not.
 */
@JvmInline
value class Note private constructor(val value: String) {
    companion object {
        const val MAX_LENGTH = 500
        private const val LINE_BREAKS_AND_TABS = "\n\r\t"

        fun parse(raw: String): Either<FieldError, Note> =
            either {
                val trimmed = raw.trim()
                ensure(trimmed.length <= MAX_LENGTH) { FieldError(Field.NOTE, ErrorCode.TOO_LONG) }
                ensure(trimmed.none { it.isISOControl() && it !in LINE_BREAKS_AND_TABS }) {
                    FieldError(Field.NOTE, ErrorCode.INVALID_FORMAT)
                }
                Note(trimmed)
            }
    }
}

enum class RejectionReason { INVALID_TICKET, DUPLICATE_CLAIM, OTHER }

sealed interface OfficerDecision {
    data class Approve(val approvedExpenses: Money) : OfficerDecision

    data class Reject(val reason: RejectionReason) : OfficerDecision
}

/**
 * Something someone wants to happen to a claim. The time is part of the
 * command: the domain never reads a clock.
 */
sealed interface ClaimCommand {
    val at: Instant

    data class Submit(val claim: ClaimDetails, override val at: Instant) : ClaimCommand

    data class Decide(
        val decision: OfficerDecision,
        val officer: OfficerId,
        val note: Note,
        override val at: Instant,
    ) : ClaimCommand

    data class RecordPayout(override val at: Instant) : ClaimCommand
}

/** Something that has happened to a claim. Events are the only thing stored. */
sealed interface ClaimEvent {
    val at: Instant

    data class Submitted(val claim: ClaimDetails, override val at: Instant) : ClaimEvent

    data class ApprovedAutomatically(val calculation: Calculation, override val at: Instant) : ClaimEvent

    data class RejectedAutomatically(val reason: IneligibilityReason, override val at: Instant) : ClaimEvent

    data class SentToReview(
        val calculation: Calculation,
        val reasons: NonEmptyList<ReviewReason>,
        override val at: Instant,
    ) : ClaimEvent

    data class ApprovedByOfficer(
        val officer: OfficerId,
        val approvedExpenses: Money,
        val note: Note,
        override val at: Instant,
    ) : ClaimEvent

    data class RejectedByOfficer(
        val officer: OfficerId,
        val reason: RejectionReason,
        val note: Note,
        override val at: Instant,
    ) : ClaimEvent

    data class PayoutRecorded(override val at: Instant) : ClaimEvent
}

sealed interface DecidedBy {
    data object Rules : DecidedBy

    data class Officer(val officer: OfficerId, val note: Note) : DecidedBy
}

sealed interface Rejection {
    data class ByRules(val reason: IneligibilityReason) : Rejection

    data class ByOfficer(
        val reason: RejectionReason,
        val officer: OfficerId,
        val note: Note,
    ) : Rejection
}

enum class StatusName { RECEIVED, AWAITING_REVIEW, APPROVED, REJECTED, PAID_OUT }

/**
 * Where a claim stands. Each state holds exactly the data that exists in it:
 * only an approved or paid claim has someone who approved it, only a rejected
 * claim has a rejection, and only a paid claim has a payout time.
 */
sealed interface ClaimState {
    data object NotSubmitted : ClaimState

    /** A claim that exists. */
    sealed interface Filed : ClaimState {
        val claim: ClaimDetails
        val submittedAt: Instant
        val status: StatusName
    }

    /** Received, with the outcome of the assessment still to come in the next event. */
    data class Received(override val claim: ClaimDetails, override val submittedAt: Instant) : Filed {
        override val status: StatusName get() = StatusName.RECEIVED
    }

    data class AwaitingReview(
        override val claim: ClaimDetails,
        override val submittedAt: Instant,
        val calculation: Calculation,
        val reasons: NonEmptyList<ReviewReason>,
    ) : Filed {
        override val status: StatusName get() = StatusName.AWAITING_REVIEW
    }

    data class Approved(
        override val claim: ClaimDetails,
        override val submittedAt: Instant,
        val calculation: Calculation,
        val by: DecidedBy,
        val decidedAt: Instant,
    ) : Filed {
        override val status: StatusName get() = StatusName.APPROVED
    }

    data class Rejected(
        override val claim: ClaimDetails,
        override val submittedAt: Instant,
        val rejection: Rejection,
        val decidedAt: Instant,
    ) : Filed {
        override val status: StatusName get() = StatusName.REJECTED
    }

    data class PaidOut(
        override val claim: ClaimDetails,
        override val submittedAt: Instant,
        val calculation: Calculation,
        val by: DecidedBy,
        val decidedAt: Instant,
        val paidAt: Instant,
    ) : Filed {
        override val status: StatusName get() = StatusName.PAID_OUT
    }
}

/** Why a command was turned down. */
sealed interface ClaimError {
    /** The claim does not exist, and the command was not a submission. */
    data object NotSubmitted : ClaimError

    /** The command makes no sense for a claim with this status. */
    data class InvalidTransition(val status: StatusName) : ClaimError

    /** An officer tried to cover more expenses than the rules allow for this claim. */
    data class ApprovedExpensesAboveLimit(val max: Money) : ClaimError
}
