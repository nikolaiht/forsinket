package io.github.nikolaiht.forsinket.app.demo

import arrow.core.Either
import arrow.core.raise.Raise
import arrow.core.raise.either
import io.github.nikolaiht.forsinket.app.ApiError
import io.github.nikolaiht.forsinket.app.ClaimService
import io.github.nikolaiht.forsinket.app.ClaimSnapshot
import io.github.nikolaiht.forsinket.app.store.ClaimStore
import io.github.nikolaiht.forsinket.app.traffic.TrafficData
import io.github.nikolaiht.forsinket.domain.ClaimDraft
import io.github.nikolaiht.forsinket.domain.ClaimId
import io.github.nikolaiht.forsinket.domain.DecisionChoiceDraft
import io.github.nikolaiht.forsinket.domain.DecisionDraft
import io.github.nikolaiht.forsinket.domain.Departure
import io.github.nikolaiht.forsinket.domain.ExpensesDraft
import io.github.nikolaiht.forsinket.domain.Outcome
import io.github.nikolaiht.forsinket.domain.RuleSet
import io.github.nikolaiht.forsinket.domain.TicketDraft
import io.github.nikolaiht.forsinket.domain.inOslo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID
import kotlin.time.Duration
import kotlin.time.Duration.Companion.hours
import kotlin.time.toJavaDuration

/**
 * Gets the demo ready when the service starts.
 *
 * A demo that resets is emptied here if the last time was [resetEvery] ago or
 * more. On a host that stops the service between visits this is the only
 * moment it can happen, because a timer in a stopped service does not fire.
 * Either way, the demo claims that are not there are put in.
 */
suspend fun prepareDemo(store: ClaimStore, traffic: TrafficData, rules: RuleSet, now: Instant, resetEvery: Duration?) {
    if (resetEvery != null) emptyIfDue(store, now, resetEvery)
    seedDemoData(store, traffic, rules, now)
}

/**
 * Starts the demo over from its seed data, if the last time was [interval] ago
 * or more. The store decides, so two instances of the service that ask at the
 * same moment do not both empty it and seed it.
 *
 * @return whether the demo started over
 */
suspend fun startOverIfDue(
    store: ClaimStore,
    traffic: TrafficData,
    rules: RuleSet,
    now: Instant,
    interval: Duration,
): Boolean {
    val emptied = emptyIfDue(store, now, interval)
    // The demo claims go in beside whatever has arrived since the store was emptied.
    if (emptied) seedDemoData(store, traffic, rules, now)
    return emptied
}

private suspend fun emptyIfDue(store: ClaimStore, now: Instant, interval: Duration): Boolean =
    withContext(Dispatchers.IO) { store.reset(now, notSince = now.minus(interval.toJavaDuration())) }

/**
 * Makes sure the demo has its six claims, so there is something to look at:
 * two waiting for an officer, one approved, one paid out, and two rejected.
 * A claim that is there already is left as it is, so this can be done again,
 * and by two instances of the service at the same moment.
 *
 * Nothing is written to the store directly. Every claim goes through the same
 * service as a claim from the web app, on a clock set to a time in the last
 * few days, so the seed data cannot be in a state the rules do not allow.
 */
suspend fun seedDemoData(store: ClaimStore, traffic: TrafficData, rules: RuleSet, now: Instant) {
    val today = now.inOslo().toLocalDate()
    // Departures from a week that ended four days ago: old enough that every
    // claim below is made after its train ran. Seven days in a row have every
    // kind of outcome the synthetic timetable can give.
    val departures = (4L..10L).flatMap { daysAgo -> traffic.departuresOn(today.minusDays(daysAgo)) }

    fun departure(nth: Int = 0, matching: (Outcome) -> Boolean): Departure =
        departures.filter { matching(it.outcome) }.getOrNull(nth)
            ?: error("the synthetic timetable has no departure for a demo claim")

    val delayed = { minutes: IntRange ->
        { outcome: Outcome -> outcome is Outcome.Ran && outcome.delayMinutes in minutes }
    }
    val cancelled = { outcome: Outcome -> outcome is Outcome.Cancelled }

    /** The service as it would have been [hoursAgo], giving a new claim the id of demo claim [number]. */
    fun serviceAt(hoursAgo: Long, number: Int = 0) =
        ClaimService(
            store = store,
            traffic = traffic,
            rules = rules,
            clock = Clock.fixed(now.minus(hoursAgo.hours.toJavaDuration()), ZoneOffset.UTC),
            newId = { demoClaimId(number) },
            maxClaims = null,
        )

    suspend fun submit(
        number: Int,
        hoursAgo: Long,
        departure: Departure,
        ticket: TicketDraft,
        expenses: ExpensesDraft? = null,
    ): Either<ApiError, ClaimSnapshot> =
        serviceAt(hoursAgo, number).submit(ClaimDraft(departure.id.value, ticket, expenses))

    suspend fun decide(
        hoursAgo: Long,
        claim: ClaimSnapshot,
        note: String,
        decision: DecisionChoiceDraft,
    ): Either<ApiError, ClaimSnapshot> =
        serviceAt(hoursAgo).decide(claim.id, claim.version, DecisionDraft("KN", note, decision))

    /**
     * One demo claim, from its first step to its last. If the claim turns out
     * to be in someone else's hands, the rest of its steps are left to them:
     * another instance of the service may be seeding at this very moment, or a
     * visitor may have got to the claim first. Any other refusal is a mistake
     * in the seed data, and stops whoever asked for the seeding.
     */
    suspend fun demoClaim(steps: suspend Raise<ApiError>.() -> Unit) {
        either { steps() }.onLeft { refusal ->
            val inOtherHands = refusal is ApiError.VersionConflict || refusal is ApiError.InvalidTransition
            check(inOtherHands) { "a demo claim was refused: $refusal" }
        }
    }

    // 1. An hour late on a single ticket: the rules approve it on their own.
    demoClaim {
        submit(1, hoursAgo = 50, departure(matching = delayed(60..119)), TicketDraft.Single(34_900)).bind()
    }

    // 2. Cancelled, with a taxi: an officer covers part of it, and it is paid out.
    demoClaim {
        val taxi = ExpensesDraft(62_000, "taxi")
        val cancelledTrain = departure(matching = cancelled)
        val withTaxi = submit(2, hoursAgo = 46, cancelledTrain, TicketDraft.Single(49_900), taxi).bind()
        val approved =
            decide(hoursAgo = 30, withTaxi, "Kvitteringen viser 500 kr.", DecisionChoiceDraft.Approve(50_000)).bind()
        serviceAt(hoursAgo = 20).recordPayout(approved.id, approved.version).bind()
    }

    // 3. More than an hour late, with expenses: an officer rejects it as a duplicate.
    demoClaim {
        val other = ExpensesDraft(95_000, "other")
        val late = departure(nth = 1, matching = delayed(60..119))
        val duplicate = submit(3, hoursAgo = 40, late, TicketDraft.Single(34_900), other).bind()
        val reject = DecisionChoiceDraft.Reject("duplicate_claim")
        decide(hoursAgo = 28, duplicate, "Samme reise er allerede erstattet.", reject).bind()
    }

    // 4. A few minutes late: under the threshold, rejected by the rules.
    demoClaim {
        submit(4, hoursAgo = 26, departure(matching = delayed(1..29)), TicketDraft.Single(34_900)).bind()
    }

    // 5 and 6. Waiting for an officer.
    demoClaim {
        val veryLate = departure(matching = delayed(120..Int.MAX_VALUE))
        submit(5, hoursAgo = 5, veryLate, TicketDraft.Single(44_900), ExpensesDraft(62_000, "taxi")).bind()
    }
    demoClaim {
        val bus = ExpensesDraft(18_000, "bus")
        submit(6, hoursAgo = 2, departure(nth = 1, matching = cancelled), TicketDraft.Period(32_900, 7), bus).bind()
    }
}

/** The same ids every time, so a link to a demo claim survives a reset. */
private fun demoClaimId(number: Int): ClaimId =
    ClaimId(UUID.nameUUIDFromBytes("forsinket-demo-claim-$number".toByteArray()))
