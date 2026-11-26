package io.github.nikolaiht.forsinket.domain

import arrow.core.NonEmptyList
import arrow.core.nonEmptyListOf
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId

/** From [fromMinutes] of delay and up, [percent] of the ticket value is paid. */
data class DelayBand(val fromMinutes: Int, val percent: Int)

/**
 * The rules a claim is assessed by, as data. A new set of terms is a new
 * [RuleSet] with a new [version], and every calculation records the version it
 * was made with.
 */
data class RuleSet(
    val version: String,
    val claimDeadlineDays: Int,
    val bands: NonEmptyList<DelayBand>,
    val expenseMinDelayMinutes: Int,
    val expenseCap: Money,
    val autoApprovalLimit: Money,
    val maxTicketPrice: Money,
    val maxClaimedExpenses: Money,
) {
    init {
        require(bands.zipWithNext().all { (lower, higher) -> lower.fromMinutes < higher.fromMinutes }) {
            "delay bands must be in ascending order"
        }
        require(bands.all { it.percent in 0..100 }) {
            "a band pays between 0 and 100 % of the ticket value"
        }
        require(bands.zipWithNext().all { (lower, higher) -> lower.percent <= higher.percent }) {
            "a longer delay must not pay less than a shorter one"
        }
    }

    /** The band an outcome falls in, or null when the delay is below the first band. */
    fun bandFor(outcome: Outcome): DelayBand? =
        when (outcome) {
            is Outcome.Ran -> bands.lastOrNull { it.fromMinutes <= outcome.delayMinutes }
            Outcome.Cancelled -> bands.last()
        }

    fun coversExpensesFor(outcome: Outcome): Boolean =
        when (outcome) {
            is Outcome.Ran -> outcome.delayMinutes >= expenseMinDelayMinutes
            Outcome.Cancelled -> true
        }
}

/** Tindbanen's terms, version 1. Fictional, made for this demo. */
val RulesV1 = RuleSet(
    version = "v1",
    claimDeadlineDays = 90,
    bands = nonEmptyListOf(
        DelayBand(fromMinutes = 30, percent = 25),
        DelayBand(fromMinutes = 60, percent = 50),
        DelayBand(fromMinutes = 120, percent = 100),
    ),
    expenseMinDelayMinutes = 60,
    expenseCap = Money.ofKroner(800),
    autoApprovalLimit = Money.ofKroner(1_000),
    maxTicketPrice = Money.ofKroner(20_000),
    maxClaimedExpenses = Money.ofKroner(10_000),
)

/** Deadlines and departure times are counted on the clock where the trains run. */
val OSLO: ZoneId = ZoneId.of("Europe/Oslo")

/** What the clock in Oslo showed at this point in time. */
fun Instant.inOslo(): LocalDateTime = atZone(OSLO).toLocalDateTime()
