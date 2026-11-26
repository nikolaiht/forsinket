package io.github.nikolaiht.forsinket.app.demo

import arrow.core.Either
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
import io.github.nikolaiht.forsinket.domain.OSLO
import io.github.nikolaiht.forsinket.domain.Outcome
import io.github.nikolaiht.forsinket.domain.RuleSet
import io.github.nikolaiht.forsinket.domain.TicketDraft
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.Clock
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.UUID

/**
 * Fills an empty store with six claims, so the demo has something to look at:
 * two waiting for an officer, one approved, one paid out, and two rejected.
 *
 * Nothing is written to the store directly. Every claim goes through the same
 * service as a claim from the web app, with a clock set to a time in the last
 * few days, so the seed data cannot be in a state the rules do not allow.
 * A store that already has claims is left as it is.
 */
suspend fun seedDemoData(store: ClaimStore, traffic: TrafficData, rules: RuleSet, now: Instant) {
    if (withContext(Dispatchers.IO) { store.count() } > 0) return

    val today = now.atZone(OSLO).toLocalDate()
    // Departures from a week that ended four days ago: old enough that every
    // claim below is made after its train ran. Seven days in a row have every
    // kind of outcome the synthetic timetable can give.
    val departures = (4L..10L).flatMap { daysAgo -> traffic.departuresOn(today.minusDays(daysAgo)) }

    fun departure(nth: Int = 0, matching: (Outcome) -> Boolean): Departure =
        departures.filter { matching(it.outcome) }.getOrNull(nth)
            ?: error("the synthetic timetable has no departure for a demo claim")

    val delayed = { minutes: IntRange -> { outcome: Outcome -> outcome is Outcome.Ran && outcome.delayMinutes in minutes } }
    val cancelled = { outcome: Outcome -> outcome is Outcome.Cancelled }

    val clock = SettableClock(now)
    var claimNumber = 0
    val service = ClaimService(
        store = store,
        traffic = traffic,
        rules = rules,
        clock = clock,
        // The same ids every time, so a link to a demo claim survives a reset.
        newId = { ClaimId(UUID.nameUUIDFromBytes("forsinket-demo-claim-${++claimNumber}".toByteArray())) },
        maxClaims = null,
    )

    suspend fun submit(hoursAgo: Long, departure: Departure, ticket: TicketDraft, expenses: ExpensesDraft? = null): ClaimSnapshot {
        clock.now = now.minus(Duration.ofHours(hoursAgo))
        return service.submit(ClaimDraft(departure.id.value, ticket, expenses)).orFail()
    }

    suspend fun decide(hoursAgo: Long, claim: ClaimSnapshot, note: String, decision: DecisionChoiceDraft): ClaimSnapshot {
        clock.now = now.minus(Duration.ofHours(hoursAgo))
        return service.decide(claim.id, claim.version, DecisionDraft("KN", note, decision)).orFail()
    }

    // 1. An hour late on a single ticket: the rules approve it on their own.
    submit(hoursAgo = 50, departure(matching = delayed(60..119)), TicketDraft.Single(34_900))

    // 2. Cancelled, with a taxi: an officer covers part of it, and it is paid out.
    val withTaxi = submit(hoursAgo = 46, departure(matching = cancelled), TicketDraft.Single(49_900), ExpensesDraft(62_000, "taxi"))
    val approved = decide(hoursAgo = 30, withTaxi, "Kvitteringen viser 500 kr.", DecisionChoiceDraft.Approve(50_000))
    clock.now = now.minus(Duration.ofHours(20))
    service.recordPayout(approved.id, approved.version).orFail()

    // 3. More than an hour late, with expenses: an officer rejects it as a duplicate.
    val duplicate = submit(hoursAgo = 40, departure(nth = 1, matching = delayed(60..119)), TicketDraft.Single(34_900), ExpensesDraft(95_000, "other"))
    decide(hoursAgo = 28, duplicate, "Samme reise er allerede erstattet.", DecisionChoiceDraft.Reject("duplicate_claim"))

    // 4. A few minutes late: under the threshold, rejected by the rules.
    submit(hoursAgo = 26, departure(matching = delayed(1..29)), TicketDraft.Single(34_900))

    // 5 and 6. Waiting for an officer.
    submit(hoursAgo = 5, departure(matching = delayed(120..Int.MAX_VALUE)), TicketDraft.Single(44_900), ExpensesDraft(62_000, "taxi"))
    submit(hoursAgo = 2, departure(nth = 1, matching = cancelled), TicketDraft.Period(32_900, 7), ExpensesDraft(18_000, "bus"))
}

/** A seed step that fails is a bug in the seed data, so it stops the start-up. */
private fun <T> Either<ApiError, T>.orFail(): T =
    fold({ error("a demo claim was refused: $it") }, { it })

private class SettableClock(var now: Instant) : Clock() {
    override fun instant(): Instant = now

    override fun getZone(): ZoneId = ZoneOffset.UTC

    override fun withZone(zone: ZoneId): Clock = this
}
