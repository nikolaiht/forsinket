package io.github.nikolaiht.forsinket.app

import arrow.core.Either
import arrow.core.NonEmptyList
import arrow.core.nonEmptyListOf
import arrow.core.raise.either
import arrow.core.raise.ensure
import io.github.nikolaiht.forsinket.app.store.ClaimStore
import io.github.nikolaiht.forsinket.app.traffic.TrafficData
import io.github.nikolaiht.forsinket.app.traffic.find
import io.github.nikolaiht.forsinket.domain.Assessment
import io.github.nikolaiht.forsinket.domain.ClaimCommand
import io.github.nikolaiht.forsinket.domain.ClaimDetails
import io.github.nikolaiht.forsinket.domain.ClaimDraft
import io.github.nikolaiht.forsinket.domain.ClaimError
import io.github.nikolaiht.forsinket.domain.ClaimId
import io.github.nikolaiht.forsinket.domain.ClaimState
import io.github.nikolaiht.forsinket.domain.DecisionDraft
import io.github.nikolaiht.forsinket.domain.DepartureId
import io.github.nikolaiht.forsinket.domain.ErrorCode
import io.github.nikolaiht.forsinket.domain.Field
import io.github.nikolaiht.forsinket.domain.FieldError
import io.github.nikolaiht.forsinket.domain.OSLO
import io.github.nikolaiht.forsinket.domain.RuleSet
import io.github.nikolaiht.forsinket.domain.StatusName
import io.github.nikolaiht.forsinket.domain.assess
import io.github.nikolaiht.forsinket.domain.decide
import io.github.nikolaiht.forsinket.domain.evolve
import io.github.nikolaiht.forsinket.domain.replay
import io.github.nikolaiht.forsinket.domain.validateClaim
import io.github.nikolaiht.forsinket.domain.validateDecision
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.Clock
import java.time.Instant
import java.time.temporal.ChronoUnit

/** Every way a request can fail that is not a bug. Each becomes one HTTP response. */
sealed interface ApiError {
    data object NotFound : ApiError

    data class Validation(val errors: NonEmptyList<FieldError>) : ApiError

    data class VersionConflict(val currentVersion: Int) : ApiError

    data class InvalidTransition(val status: StatusName) : ApiError

    data class MalformedRequest(val detail: String) : ApiError

    data object DemoLimitReached : ApiError
}

/**
 * The imperative shell. Everything the domain is not allowed to do happens
 * here: reading the clock, making ids, looking up departures, and loading and
 * storing events. Every operation that changes a claim has the same shape:
 * load the events, fold them to a state, let the domain decide, store what it
 * decided.
 *
 * @param maxClaims a cap on stored claims for the open demo, or null for none
 */
class ClaimService(
    private val store: ClaimStore,
    private val traffic: TrafficData,
    private val rules: RuleSet,
    private val clock: Clock,
    private val newId: () -> ClaimId,
    private val maxClaims: Int?,
) {
    /** What the rules would say about a claim, without recording anything. */
    suspend fun preview(draft: ClaimDraft): Either<ApiError, Assessment> =
        either {
            val now = now()
            val claim = validated(draft, now).bind()
            assess(rules, claim, now.atZone(OSLO).toLocalDate())
        }

    suspend fun submit(draft: ClaimDraft): Either<ApiError, ClaimSnapshot> =
        either {
            val now = now()
            val claim = validated(draft, now).bind()
            ensure(maxClaims == null || io { store.count() } < maxClaims) { ApiError.DemoLimitReached }
            execute(newId(), expectedVersion = 0, ClaimCommand.Submit(claim, now)).bind()
        }

    suspend fun get(id: ClaimId): Either<ApiError, ClaimSnapshot> =
        either {
            val events = io { store.load(id) }
            val state = replay(events)
            ensure(state is ClaimState.Filed) { ApiError.NotFound }
            ClaimSnapshot(id, events.size, state, events)
        }

    suspend fun list(status: StatusName?): List<ClaimSummary> =
        io { store.summaries(status) }

    suspend fun decide(id: ClaimId, expectedVersion: Int, draft: DecisionDraft): Either<ApiError, ClaimSnapshot> =
        either {
            val command = validateDecision(draft, now()).mapLeft(ApiError::Validation).bind()
            execute(id, expectedVersion, command).bind()
        }

    suspend fun recordPayout(id: ClaimId, expectedVersion: Int): Either<ApiError, ClaimSnapshot> =
        execute(id, expectedVersion, ClaimCommand.RecordPayout(now()))

    /**
     * Load, decide, store. [expectedVersion] is the version the caller last
     * saw. If the claim has moved on, the command is not even tried: a
     * decision is only valid for the claim it was made on.
     */
    private suspend fun execute(
        id: ClaimId,
        expectedVersion: Int,
        command: ClaimCommand,
    ): Either<ApiError, ClaimSnapshot> =
        either {
            val history = io { store.load(id) }
            ensure(history.size == expectedVersion) {
                if (history.isEmpty()) ApiError.NotFound else ApiError.VersionConflict(history.size)
            }

            val before = replay(history)
            val events = decide(rules, before, command).mapLeft(::apiError).bind()
            val after = events.fold(before, ::evolve)
            check(after is ClaimState.Filed) { "an accepted command left the claim without a state" }
            val snapshot = ClaimSnapshot(id, history.size + events.size, after, history + events)

            io { store.append(id, expectedVersion, events, summarize(snapshot)) }
                .mapLeft { conflict -> ApiError.VersionConflict(conflict.currentVersion) }
                .bind()
            snapshot
        }

    private suspend fun validated(draft: ClaimDraft, now: Instant): Either<ApiError, ClaimDetails> {
        val departure = io { traffic.find(DepartureId(draft.departureId)) }
        return validateClaim(rules, draft, departure, now = now.atZone(OSLO).toLocalDateTime())
            .mapLeft(ApiError::Validation)
    }

    /** Milliseconds are as fine as a browser reads a timestamp, so nothing finer is recorded. */
    private fun now(): Instant = clock.instant().truncatedTo(ChronoUnit.MILLIS)
}

private fun apiError(error: ClaimError): ApiError =
    when (error) {
        ClaimError.NotSubmitted ->
            ApiError.NotFound

        is ClaimError.InvalidTransition ->
            ApiError.InvalidTransition(error.status)

        is ClaimError.ApprovedExpensesAboveLimit ->
            ApiError.Validation(nonEmptyListOf(FieldError(Field.APPROVED_EXPENSES, ErrorCode.ABOVE_MAXIMUM)))
    }

/** JDBC blocks, so calls to the store are moved off the threads that serve requests. */
private suspend fun <T> io(block: () -> T): T =
    withContext(Dispatchers.IO) { block() }
