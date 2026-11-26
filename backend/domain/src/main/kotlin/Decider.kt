package io.github.nikolaiht.forsinket.domain

import arrow.core.Either
import arrow.core.NonEmptyList
import arrow.core.nonEmptyListOf
import arrow.core.raise.Raise
import arrow.core.raise.either
import arrow.core.raise.ensure
import io.github.nikolaiht.forsinket.domain.ClaimCommand.Decide
import io.github.nikolaiht.forsinket.domain.ClaimCommand.RecordPayout
import io.github.nikolaiht.forsinket.domain.ClaimCommand.Submit

/**
 * The whole life of a claim is two pure functions.
 *
 * [decide] looks at where a claim stands and at a command, and answers with
 * the events that follow, or with the reason the command is turned down.
 * [evolve] applies one event to a state. Nothing here stores, sends or reads
 * anything; the shell around the domain loads the events, calls these, and
 * saves what [decide] returned.
 */
fun decide(rules: RuleSet, state: ClaimState, command: ClaimCommand): Either<ClaimError, NonEmptyList<ClaimEvent>> =
    either {
        when (state) {
            ClaimState.NotSubmitted ->
                when (command) {
                    is Submit -> submit(rules, command)
                    is Decide, is RecordPayout -> raise(ClaimError.NotSubmitted)
                }

            is ClaimState.AwaitingReview ->
                when (command) {
                    is Decide -> nonEmptyListOf(review(state, command))
                    is Submit, is RecordPayout -> raise(ClaimError.InvalidTransition(state.status))
                }

            is ClaimState.Approved ->
                when (command) {
                    is RecordPayout -> nonEmptyListOf(ClaimEvent.PayoutRecorded(command.at))
                    is Submit, is Decide -> raise(ClaimError.InvalidTransition(state.status))
                }

            is ClaimState.Received ->
                raise(ClaimError.InvalidTransition(state.status))

            // Final states: nothing more can happen to the claim.
            is ClaimState.Rejected ->
                raise(ClaimError.InvalidTransition(state.status))

            is ClaimState.PaidOut ->
                raise(ClaimError.InvalidTransition(state.status))
        }
    }

/** Receiving a claim and assessing it are two facts, so they are two events. */
private fun submit(rules: RuleSet, command: Submit): NonEmptyList<ClaimEvent> {
    val submittedOn = command.at.inOslo().toLocalDate()
    val outcome =
        when (val assessment = assess(rules, command.claim, submittedOn)) {
            is Assessment.NotEligible ->
                ClaimEvent.RejectedAutomatically(assessment.reason, command.at)

            is Assessment.Eligible ->
                when (val handling = assessment.handling) {
                    Handling.AutoApprove ->
                        ClaimEvent.ApprovedAutomatically(assessment.calculation, command.at)

                    is Handling.ManualReview ->
                        ClaimEvent.SentToReview(assessment.calculation, handling.reasons, command.at)
                }
        }
    return nonEmptyListOf(ClaimEvent.Submitted(command.claim, command.at), outcome)
}

/**
 * An officer decides how much of the expenses to cover, or rejects the claim.
 * The ticket compensation follows from the rules and is not theirs to change.
 */
private fun Raise<ClaimError>.review(state: ClaimState.AwaitingReview, command: Decide): ClaimEvent =
    when (val decision = command.decision) {
        is OfficerDecision.Approve -> {
            val max = state.calculation.expenses.maxCoverable
            ensure(decision.approvedExpenses <= max) { ClaimError.ApprovedExpensesAboveLimit(max) }
            ClaimEvent.ApprovedByOfficer(command.officer, decision.approvedExpenses, command.note, command.at)
        }

        is OfficerDecision.Reject ->
            ClaimEvent.RejectedByOfficer(command.officer, decision.reason, command.note, command.at)
    }

private val ExpenseAssessment.maxCoverable: Money
    get() =
        when (this) {
            is ExpenseAssessment.PendingReview -> maxCoverable
            ExpenseAssessment.NoneClaimed, is ExpenseAssessment.NotCovered, is ExpenseAssessment.Covered -> Money.ZERO
        }

fun evolve(state: ClaimState, event: ClaimEvent): ClaimState =
    when (event) {
        is ClaimEvent.Submitted ->
            state.expecting<ClaimState.NotSubmitted>(event) {
                ClaimState.Received(event.claim, event.at)
            }

        is ClaimEvent.ApprovedAutomatically ->
            state.expecting<ClaimState.Received>(event) {
                ClaimState.Approved(it.claim, it.submittedAt, event.calculation, DecidedBy.Rules, event.at)
            }

        is ClaimEvent.RejectedAutomatically ->
            state.expecting<ClaimState.Received>(event) {
                ClaimState.Rejected(it.claim, it.submittedAt, Rejection.ByRules(event.reason), event.at)
            }

        is ClaimEvent.SentToReview ->
            state.expecting<ClaimState.Received>(event) {
                ClaimState.AwaitingReview(it.claim, it.submittedAt, event.calculation, event.reasons)
            }

        is ClaimEvent.ApprovedByOfficer ->
            state.expecting<ClaimState.AwaitingReview>(event) {
                ClaimState.Approved(
                    it.claim,
                    it.submittedAt,
                    it.calculation.withCoveredExpenses(event.approvedExpenses),
                    DecidedBy.Officer(event.officer, event.note),
                    event.at,
                )
            }

        is ClaimEvent.RejectedByOfficer ->
            state.expecting<ClaimState.AwaitingReview>(event) {
                ClaimState.Rejected(
                    it.claim,
                    it.submittedAt,
                    Rejection.ByOfficer(event.reason, event.officer, event.note),
                    event.at,
                )
            }

        is ClaimEvent.PayoutRecorded ->
            state.expecting<ClaimState.Approved>(event) {
                ClaimState.PaidOut(it.claim, it.submittedAt, it.calculation, it.by, it.decidedAt, event.at)
            }
    }

fun replay(events: List<ClaimEvent>): ClaimState = events.fold(ClaimState.NotSubmitted, ::evolve)

/**
 * An event that does not fit the state it is applied to cannot have come from
 * [decide]. That is corrupt data, not something a passenger or an officer did,
 * so it is an exception and not a [ClaimError].
 */
private inline fun <reified S : ClaimState> ClaimState.expecting(
    event: ClaimEvent,
    next: (S) -> ClaimState,
): ClaimState =
    if (this is S) {
        next(this)
    } else {
        error("corrupt event stream: ${event::class.simpleName} cannot follow ${this::class.simpleName}")
    }

private fun Calculation.withCoveredExpenses(approved: Money): Calculation =
    when (val pending = expenses) {
        is ExpenseAssessment.PendingReview ->
            copy(expenses = ExpenseAssessment.Covered(claimed = pending.claimed, approved = approved))

        ExpenseAssessment.NoneClaimed, is ExpenseAssessment.NotCovered, is ExpenseAssessment.Covered -> {
            // decide only lets an officer cover expenses that were up for review.
            check(approved == Money.ZERO) { "corrupt event stream: expenses approved that were not up for review" }
            this
        }
    }
