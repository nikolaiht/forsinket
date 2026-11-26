package io.github.nikolaiht.forsinket.domain

import arrow.core.left
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldBeIn
import io.kotest.matchers.collections.shouldContainAll
import io.kotest.matchers.comparables.shouldBeLessThanOrEqualTo
import io.kotest.matchers.shouldBe
import io.kotest.matchers.types.shouldBeInstanceOf
import io.kotest.property.Arb
import io.kotest.property.arbitrary.list
import io.kotest.property.checkAll

/**
 * What happened when a list of commands was thrown at a claim: the commands
 * [decide] accepted were applied, the rest were skipped.
 */
private data class Run(
    val state: ClaimState,
    val events: List<ClaimEvent>,
    val trail: List<ClaimState>,
)

private fun run(commands: List<ClaimCommand>): Run =
    commands.fold(Run(ClaimState.NotSubmitted, emptyList(), listOf(ClaimState.NotSubmitted))) { run, command ->
        decide(RulesV1, run.state, command).fold(
            ifLeft = { run },
            ifRight = { events ->
                val next = events.fold(run.state, ::evolve)
                Run(next, run.events + events, run.trail + next)
            },
        )
    }

private val ClaimState.statusOrNull: StatusName?
    get() = (this as? ClaimState.Filed)?.status

/** Every move the state diagram allows, as (from, to). Null is a claim that does not exist yet. */
private val allowedMoves: Set<Pair<StatusName?, StatusName>> =
    setOf(
        null to StatusName.APPROVED,
        null to StatusName.REJECTED,
        null to StatusName.AWAITING_REVIEW,
        StatusName.AWAITING_REVIEW to StatusName.APPROVED,
        StatusName.AWAITING_REVIEW to StatusName.REJECTED,
        StatusName.APPROVED to StatusName.PAID_OUT,
    )

class DeciderPropertyTest : FunSpec({
    val commands = Arb.list(Arb.command(), 0..12)

    test("the generated command lists reach every status a claim can rest in") {
        val reached = mutableSetOf<StatusName>()
        checkAll(commands) { list ->
            run(list).trail.mapNotNullTo(reached) { it.statusOrNull }
        }

        reached shouldContainAll
            listOf(StatusName.AWAITING_REVIEW, StatusName.APPROVED, StatusName.REJECTED, StatusName.PAID_OUT)
    }

    test("every event decide produces can be applied, and replaying them gives the same state") {
        checkAll(commands) { list ->
            val run = run(list)

            replay(run.events) shouldBe run.state
        }
    }

    test("a claim only ever moves along the state diagram") {
        checkAll(commands) { list ->
            run(list).trail.zipWithNext().forEach { (before, after) ->
                (before.statusOrNull to after.statusOrNull) shouldBeIn allowedMoves
            }
        }
    }

    test("a claim is never left as merely received") {
        checkAll(commands) { list ->
            run(list).state.statusOrNull shouldBeIn StatusName.entries.minus(StatusName.RECEIVED).plus(null)
        }
    }

    test("nothing more can happen to a rejected or paid claim") {
        checkAll(commands, Arb.command()) { list, next ->
            val state = run(list).state
            if (state is ClaimState.Rejected || state is ClaimState.PaidOut) {
                decide(RulesV1, state, next) shouldBe ClaimError.InvalidTransition(state.status).left()
            }
        }
    }

    test("a paid claim was approved first") {
        checkAll(commands) { list ->
            run(list).trail.zipWithNext().forEach { (before, after) ->
                if (after is ClaimState.PaidOut) {
                    before.shouldBeInstanceOf<ClaimState.Approved>()
                }
            }
        }
    }

    test("no officer can make a claim pay more for expenses than was claimed or the cap allows") {
        checkAll(commands) { list ->
            val state = run(list).state
            val calculation =
                when (state) {
                    is ClaimState.Approved -> state.calculation
                    is ClaimState.PaidOut -> state.calculation
                    else -> null
                }
            if (calculation != null) {
                val claimed = (state as ClaimState.Filed).claim.expenses?.amount ?: Money.ZERO

                calculation.expenses.covered shouldBeLessThanOrEqualTo claimed
                calculation.expenses.covered shouldBeLessThanOrEqualTo RulesV1.expenseCap
                calculation.total shouldBeLessThanOrEqualTo state.claim.ticket.price + RulesV1.expenseCap
            }
        }
    }
})
