package io.github.nikolaiht.forsinket.domain

import arrow.core.EitherNel
import arrow.core.raise.Raise
import arrow.core.raise.either
import arrow.core.raise.ensure
import arrow.core.raise.zipOrAccumulate
import java.time.Instant

/** An officer's decision as it arrives: parsed, not yet checked. */
data class DecisionDraft(
    val officer: String,
    val note: String,
    val decision: DecisionChoiceDraft,
)

sealed interface DecisionChoiceDraft {
    data class Approve(val approvedExpensesOre: Long) : DecisionChoiceDraft

    data class Reject(val reason: String) : DecisionChoiceDraft
}

/**
 * Checks what can be checked without knowing the claim. Whether the approved
 * expenses are within what this particular claim allows is for [decide], which
 * has the claim's state.
 */
fun validateDecision(draft: DecisionDraft, at: Instant): EitherNel<FieldError, ClaimCommand.Decide> =
    either {
        zipOrAccumulate(
            { OfficerId.parse(draft.officer).bind() },
            { note(draft) },
            { decision(draft.decision) },
        ) { officer, note, decision ->
            ClaimCommand.Decide(decision, officer, note, at)
        }
    }

/** A rejection has to be explained. An approval may speak for itself. */
private fun Raise<FieldError>.note(draft: DecisionDraft): Note {
    val note = Note.parse(draft.note).bind()
    ensure(draft.decision is DecisionChoiceDraft.Approve || note.value.isNotEmpty()) {
        FieldError(Field.NOTE, ErrorCode.REQUIRED)
    }
    return note
}

private fun Raise<FieldError>.decision(draft: DecisionChoiceDraft): OfficerDecision =
    when (draft) {
        is DecisionChoiceDraft.Approve -> {
            ensure(draft.approvedExpensesOre >= 0) {
                FieldError(Field.APPROVED_EXPENSES, ErrorCode.MUST_NOT_BE_NEGATIVE)
            }
            OfficerDecision.Approve(Money.ofOre(draft.approvedExpensesOre))
        }

        is DecisionChoiceDraft.Reject ->
            OfficerDecision.Reject(enumValue<RejectionReason>(Field.DECISION_REASON, draft.reason))
    }
