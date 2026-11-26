package io.github.nikolaiht.forsinket.domain

import arrow.core.Either
import arrow.core.NonEmptyList
import arrow.core.nonEmptyListOf
import io.kotest.property.Arb
import io.kotest.property.arbitrary.Codepoint
import io.kotest.property.arbitrary.az
import io.kotest.property.arbitrary.bind
import io.kotest.property.arbitrary.choice
import io.kotest.property.arbitrary.constant
import io.kotest.property.arbitrary.enum
import io.kotest.property.arbitrary.int
import io.kotest.property.arbitrary.long
import io.kotest.property.arbitrary.map
import io.kotest.property.arbitrary.of
import io.kotest.property.arbitrary.orNull
import io.kotest.property.arbitrary.string
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime

/** The travel date the hand-written examples use. A Friday. */
val exampleDate: LocalDate = LocalDate.of(2026, 11, 20)

fun departure(outcome: Outcome, date: LocalDate = exampleDate): Departure =
    Departure(
        id = DepartureId("$date-TB16"),
        date = date,
        trainNumber = "TB16",
        origin = "Storhavn",
        destination = "Fjordvik",
        scheduledDeparture = LocalTime.of(16, 42),
        outcome = outcome,
    )

fun departure(delayMinutes: Int, date: LocalDate = exampleDate): Departure =
    departure(Outcome.Ran(delayMinutes), date)

fun cancelledDeparture(date: LocalDate = exampleDate): Departure =
    departure(Outcome.Cancelled, date)

fun Arb.Companion.money(range: LongRange): Arb<Money> =
    Arb.long(range).map(Money::ofOre)

/** Any ticket the validation accepts: a price from 1 øre up to the cap. */
fun Arb.Companion.ticket(): Arb<Ticket> =
    Arb.choice(
        Arb.money(1L..RulesV1.maxTicketPrice.ore).map { Ticket.Single(it) },
        Arb.bind(Arb.money(1L..RulesV1.maxTicketPrice.ore), Arb.enum<Validity>()) { price, validity ->
            Ticket.Period(price, validity)
        },
    )

/**
 * Any outcome. The minutes on either side of each limit in the rules are
 * generated on purpose, not left to chance.
 */
fun Arb.Companion.outcome(): Arb<Outcome> =
    Arb.choice(
        Arb.int(0..300).map { Outcome.Ran(it) },
        Arb.of(0, 29, 30, 59, 60, 119, 120).map { Outcome.Ran(it) },
        Arb.constant(Outcome.Cancelled),
    )

fun Arb.Companion.expenses(): Arb<Expenses?> =
    Arb.bind(Arb.money(1L..RulesV1.maxClaimedExpenses.ore), Arb.enum<ExpenseKind>()) { amount, kind ->
        Expenses(amount, kind)
    }.orNull(0.5)

/** Claims for departures on [date]. By default every claim is for [exampleDate]. */
fun Arb.Companion.claimDetails(date: Arb<LocalDate> = Arb.constant(exampleDate)): Arb<ClaimDetails> =
    Arb.bind(Arb.outcome(), date, Arb.ticket(), Arb.expenses()) { outcome, travelDate, ticket, expenses ->
        ClaimDetails(departure(outcome, travelDate), ticket, expenses)
    }

/** Any day in 2026. */
fun Arb.Companion.dateIn2026(): Arb<LocalDate> =
    Arb.int(0..364).map { LocalDate.of(2026, 1, 1).plusDays(it.toLong()) }

/** Any millisecond in 2026: the precision the service records. */
fun Arb.Companion.instant(): Arb<Instant> =
    Arb.long(1_767_225_600_000L..1_798_761_599_999L).map(Instant::ofEpochMilli)

fun Arb.Companion.officerId(): Arb<OfficerId> =
    Arb.string(2..10, Codepoint.az()).map(::officerId)

/** Notes with the characters that are easy to get wrong in JSON and SQL. */
fun Arb.Companion.note(): Arb<Note> =
    Arb.choice(
        Arb.string(0..80),
        Arb.of("Kvitteringen viser 500 kr.", "Æ, ø og å. «Sitat» – og tankestrek.", "To\nlinjer", "'; DROP TABLE claim_events; --"),
    ).map(::note)

fun Arb.Companion.officerDecision(): Arb<OfficerDecision> =
    Arb.choice(
        Arb.money(0L..100_000L).map { OfficerDecision.Approve(it) },
        Arb.enum<RejectionReason>().map { OfficerDecision.Reject(it) },
    )

/** Any command, for claims that may be on time, too late, or anything in between. */
fun Arb.Companion.command(): Arb<ClaimCommand> =
    Arb.choice(
        Arb.bind(Arb.claimDetails(Arb.dateIn2026()), Arb.instant()) { claim, at ->
            ClaimCommand.Submit(claim, at)
        },
        Arb.bind(Arb.officerDecision(), Arb.officerId(), Arb.note(), Arb.instant()) { decision, officer, note, at ->
            ClaimCommand.Decide(decision, officer, note, at)
        },
        Arb.instant().map { ClaimCommand.RecordPayout(it) },
    )

fun Arb.Companion.ticketValue(): Arb<TicketValue> =
    Arb.choice(
        Arb.money(0L..2_000_000L).map { TicketValue.FullPrice(it) },
        Arb.bind(Arb.money(1L..2_000_000L), Arb.enum<Validity>()) { price, validity ->
            TicketValue.PerDay(price, validity.days, price.dividedBy(validity.days))
        },
    )

fun Arb.Companion.expenseAssessment(): Arb<ExpenseAssessment> =
    Arb.choice(
        Arb.constant(ExpenseAssessment.NoneClaimed),
        Arb.money(1L..1_000_000L).map { ExpenseAssessment.NotCovered(it) },
        Arb.bind(Arb.money(1L..1_000_000L), Arb.money(0L..80_000L)) { claimed, max ->
            ExpenseAssessment.PendingReview(claimed, max)
        },
        Arb.bind(Arb.money(1L..1_000_000L), Arb.money(0L..80_000L)) { claimed, approved ->
            ExpenseAssessment.Covered(claimed, approved)
        },
    )

/** Any well-formed calculation, whether or not the rules could have produced it. */
fun Arb.Companion.calculation(): Arb<Calculation> =
    Arb.bind(
        Arb.ticketValue(),
        Arb.outcome(),
        Arb.of(25, 50, 100),
        Arb.money(0L..2_000_000L),
        Arb.expenseAssessment(),
    ) { ticketValue, outcome, percent, compensation, expenses ->
        Calculation("v1", ticketValue, outcome, percent, compensation, expenses)
    }

fun Arb.Companion.reviewReasons(): Arb<NonEmptyList<ReviewReason>> =
    Arb.of(
        nonEmptyListOf(ReviewReason.EXPENSES_CLAIMED),
        nonEmptyListOf(ReviewReason.ABOVE_AUTO_APPROVAL_LIMIT),
        nonEmptyListOf(ReviewReason.EXPENSES_CLAIMED, ReviewReason.ABOVE_AUTO_APPROVAL_LIMIT),
    )

/** Any single event, for checking that storage keeps every one of them intact. */
fun Arb.Companion.claimEvent(): Arb<ClaimEvent> =
    Arb.choice(
        Arb.bind(Arb.claimDetails(Arb.dateIn2026()), Arb.instant()) { claim, at ->
            ClaimEvent.Submitted(claim, at)
        },
        Arb.bind(Arb.calculation(), Arb.instant()) { calculation, at ->
            ClaimEvent.ApprovedAutomatically(calculation, at)
        },
        Arb.bind(Arb.enum<IneligibilityReason>(), Arb.instant()) { reason, at ->
            ClaimEvent.RejectedAutomatically(reason, at)
        },
        Arb.bind(Arb.calculation(), Arb.reviewReasons(), Arb.instant()) { calculation, reasons, at ->
            ClaimEvent.SentToReview(calculation, reasons, at)
        },
        Arb.bind(Arb.officerId(), Arb.money(0L..80_000L), Arb.note(), Arb.instant()) { officer, approved, note, at ->
            ClaimEvent.ApprovedByOfficer(officer, approved, note, at)
        },
        Arb.bind(Arb.officerId(), Arb.enum<RejectionReason>(), Arb.note(), Arb.instant()) { officer, reason, note, at ->
            ClaimEvent.RejectedByOfficer(officer, reason, note, at)
        },
        Arb.instant().map { ClaimEvent.PayoutRecorded(it) },
    )

fun officerId(raw: String): OfficerId =
    OfficerId.parse(raw).fold({ error("not a valid officer id in a test: $raw") }, { it })

fun note(raw: String): Note =
    Note.parse(raw).fold({ error("not a valid note in a test: $raw") }, { it })

/** The value of an Either that must be a Right, with the Left in the message when it is not. */
fun <A, B> Either<A, B>.shouldBeRight(): B =
    fold({ throw AssertionError("expected a Right, but got Left($it)") }, { it })
