package io.github.nikolaiht.forsinket.app.demo

import arrow.core.Either
import arrow.core.getOrElse
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
import java.time.Duration
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID

/** Seeds the demo claims at start-up, unless the store already has claims in it. */
suspend fun seedIfEmpty(store: ClaimStore, traffic: TrafficData, rules: RuleSet, now: Instant) {
    if (withContext(Dispatchers.IO) { store.count() } == 0) {
        seedDemoData(store, traffic, rules, now)
    }
}

/**
 * Adds six claims, so the demo has something to look at: two waiting for an
 * officer, one approved, one paid out, and two rejected.
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
            clock = Clock.fixed(now.minus(Duration.ofHours(hoursAgo)), ZoneOffset.UTC),
            newId = { demoClaimId(number) },
            maxClaims = null,
        )

    suspend fun submit(
        number: Int,
        hoursAgo: Long,
        departure: Departure,
        ticket: TicketDraft,
        expenses: ExpensesDraft? = null,
    ): ClaimSnapshot = serviceAt(hoursAgo, number).submit(ClaimDraft(departure.id.value, ticket, expenses)).orFail()

    suspend fun decide(
        hoursAgo: Long,
        claim: ClaimSnapshot,
        note: String,
        decision: DecisionChoiceDraft,
    ): ClaimSnapshot = serviceAt(hoursAgo).decide(claim.id, claim.version, DecisionDraft("KN", note, decision)).orFail()

    // 1. An hour late on a single ticket: the rules approve it on their own.
    submit(1, hoursAgo = 50, departure(matching = delayed(60..119)), TicketDraft.Single(34_900))

    // 2. Cancelled, with a taxi: an officer covers part of it, and it is paid out.
    val withTaxi =
        submit(
            2,
            hoursAgo = 46,
            departure(matching = cancelled),
            TicketDraft.Single(49_900),
            ExpensesDraft(62_000, "taxi"),
        )
    val approved = decide(hoursAgo = 30, withTaxi, "Kvitteringen viser 500 kr.", DecisionChoiceDraft.Approve(50_000))
    serviceAt(hoursAgo = 20).recordPayout(approved.id, approved.version).orFail()

    // 3. More than an hour late, with expenses: an officer rejects it as a duplicate.
    val duplicate =
        submit(
            3,
            hoursAgo = 40,
            departure(nth = 1, matching = delayed(60..119)),
            TicketDraft.Single(34_900),
            ExpensesDraft(95_000, "other"),
        )
    decide(
        hoursAgo = 28,
        duplicate,
        "Samme reise er allerede erstattet.",
        DecisionChoiceDraft.Reject("duplicate_claim"),
    )

    // 4. A few minutes late: under the threshold, rejected by the rules.
    submit(4, hoursAgo = 26, departure(matching = delayed(1..29)), TicketDraft.Single(34_900))

    // 5 and 6. Waiting for an officer.
    submit(
        5,
        hoursAgo = 5,
        departure(matching = delayed(120..Int.MAX_VALUE)),
        TicketDraft.Single(44_900),
        ExpensesDraft(62_000, "taxi"),
    )
    submit(
        6,
        hoursAgo = 2,
        departure(nth = 1, matching = cancelled),
        TicketDraft.Period(32_900, 7),
        ExpensesDraft(18_000, "bus"),
    )
}

/** The same ids every time, so a link to a demo claim survives a reset. */
private fun demoClaimId(number: Int): ClaimId =
    ClaimId(UUID.nameUUIDFromBytes("forsinket-demo-claim-$number".toByteArray()))

/** A seed step that is refused is a bug in the seed data, so it stops whoever asked for the seeding. */
private fun <T> Either<ApiError, T>.orFail(): T = getOrElse { error("a demo claim was refused: $it") }
