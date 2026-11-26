package io.github.nikolaiht.forsinket.app

import io.github.nikolaiht.forsinket.app.json.AppJson
import io.github.nikolaiht.forsinket.app.traffic.SyntheticTrafficData
import io.github.nikolaiht.forsinket.app.traffic.find
import io.github.nikolaiht.forsinket.domain.ClaimCommand
import io.github.nikolaiht.forsinket.domain.ClaimDetails
import io.github.nikolaiht.forsinket.domain.ClaimEvent
import io.github.nikolaiht.forsinket.domain.ClaimId
import io.github.nikolaiht.forsinket.domain.ClaimState
import io.github.nikolaiht.forsinket.domain.Departure
import io.github.nikolaiht.forsinket.domain.DepartureId
import io.github.nikolaiht.forsinket.domain.ExpenseKind
import io.github.nikolaiht.forsinket.domain.Expenses
import io.github.nikolaiht.forsinket.domain.Money
import io.github.nikolaiht.forsinket.domain.OfficerDecision
import io.github.nikolaiht.forsinket.domain.RejectionReason
import io.github.nikolaiht.forsinket.domain.RulesV1
import io.github.nikolaiht.forsinket.domain.Ticket
import io.github.nikolaiht.forsinket.domain.Validity
import io.github.nikolaiht.forsinket.domain.decide
import io.github.nikolaiht.forsinket.domain.evolve
import io.github.nikolaiht.forsinket.domain.note
import io.github.nikolaiht.forsinket.domain.officerId
import kotlinx.serialization.json.JsonElement
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.util.UUID

/** Reads one of the hand-written examples in `contract/examples`. */
fun contractExample(name: String): JsonElement =
    AppJson.parseToJsonElement(File(System.getProperty("contract.examples"), name).readText())

/**
 * The domain values behind the contract examples A to E: the same claims, ids
 * and times as the JSON files, built here from the domain so that the tests
 * compare two independent descriptions of the same thing.
 */
object ContractFixtures {
    val day: LocalDate = LocalDate.of(2026, 11, 20)

    private fun departure(id: String): Departure =
        SyntheticTrafficData.find(DepartureId(id)) ?: error("no such departure in the synthetic timetable: $id")

    val idA = ClaimId(UUID.fromString("0a6f3c1e-5b7d-4e2a-9c41-7d2f8b3e6a10"))
    val idB = ClaimId(UUID.fromString("3f9d2b7a-1c4e-4f8b-a6d5-2e7c9b1f4d30"))
    val idC = ClaimId(UUID.fromString("c81e4a2d-9f6b-4d3c-8e17-5a2b6c9d0e50"))

    val submittedA: Instant = Instant.parse("2026-11-21T09:15:00Z")
    val submittedB: Instant = Instant.parse("2026-11-21T10:00:00Z")
    val submittedC: Instant = Instant.parse("2026-11-21T11:00:00Z")
    val decidedAt: Instant = Instant.parse("2026-11-21T12:30:00Z")
    val paidAt: Instant = Instant.parse("2026-11-22T08:00:00Z")

    val claimA = ClaimDetails(departure("2026-11-20-FB16"), Ticket.Single(Money.ofKroner(349)), expenses = null)
    val claimB = ClaimDetails(
        departure("2026-11-20-FB14"),
        Ticket.Period(Money.ofKroner(849), Validity.THIRTY_DAYS),
        Expenses(Money.ofKroner(620), ExpenseKind.TAXI),
    )
    val claimC = ClaimDetails(departure("2026-11-20-FB17"), Ticket.Single(Money.ofKroner(349)), expenses = null)

    const val RECEIPT_NOTE = "Kvitteringen viser 500 kr."
    const val DUPLICATE_NOTE = "Samme reise er allerede erstattet."

    private val approve500 =
        ClaimCommand.Decide(OfficerDecision.Approve(Money.ofKroner(500)), officerId("KN"), note(RECEIPT_NOTE), decidedAt)
    private val rejectDuplicate =
        ClaimCommand.Decide(
            OfficerDecision.Reject(RejectionReason.DUPLICATE_CLAIM),
            officerId("KN"),
            note(DUPLICATE_NOTE),
            decidedAt,
        )

    val approvedAutomatically = snapshot(idA, ClaimCommand.Submit(claimA, submittedA))
    val paidOut = snapshot(idA, ClaimCommand.Submit(claimA, submittedA), ClaimCommand.RecordPayout(paidAt))
    val awaitingReview = snapshot(idB, ClaimCommand.Submit(claimB, submittedB))
    val approvedByOfficer = snapshot(idB, ClaimCommand.Submit(claimB, submittedB), approve500)
    val rejectedByOfficer = snapshot(idB, ClaimCommand.Submit(claimB, submittedB), rejectDuplicate)
    val rejectedByRules = snapshot(idC, ClaimCommand.Submit(claimC, submittedC))

    /** The claim as it stands after [commands], each of which must be accepted. */
    private fun snapshot(id: ClaimId, vararg commands: ClaimCommand): ClaimSnapshot {
        val start: Pair<ClaimState, List<ClaimEvent>> = ClaimState.NotSubmitted to emptyList()
        val (state, events) = commands.fold(start) { (state, events), command ->
            val produced = decide(RulesV1, state, command)
                .fold({ error("$command was rejected in a fixture: $it") }, { it })
            produced.fold(state, ::evolve) to events + produced
        }
        return checkNotNull(snapshotOf(id, events))
    }
}
