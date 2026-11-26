package io.github.nikolaiht.forsinket.app

import io.github.nikolaiht.forsinket.domain.Calculation
import io.github.nikolaiht.forsinket.domain.ClaimEvent
import io.github.nikolaiht.forsinket.domain.ClaimId
import io.github.nikolaiht.forsinket.domain.ClaimState
import io.github.nikolaiht.forsinket.domain.Money
import io.github.nikolaiht.forsinket.domain.StatusName
import java.time.Instant
import java.time.LocalDate

/**
 * A claim as read from the store: its events, the state they fold to, and the
 * version, which is the number of events. A writer has to say which version it
 * saw, so two writers cannot both build on the same one.
 */
data class ClaimSnapshot(
    val id: ClaimId,
    val version: Int,
    val state: ClaimState.Filed,
    val events: List<ClaimEvent>,
)

/** One row in the list of claims. A projection of the events, kept for querying. */
data class ClaimSummary(
    val id: ClaimId,
    val version: Int,
    val status: StatusName,
    val submittedAt: Instant,
    val departureDate: LocalDate,
    val trainNumber: String,
    val total: Money?,
)

fun summarize(snapshot: ClaimSnapshot): ClaimSummary =
    ClaimSummary(
        id = snapshot.id,
        version = snapshot.version,
        status = snapshot.state.status,
        submittedAt = snapshot.state.submittedAt,
        departureDate = snapshot.state.claim.departure.date,
        trainNumber = snapshot.state.claim.departure.trainNumber,
        total = snapshot.state.calculation?.total,
    )

/** The calculation of a claim that has one. A received or rejected claim has none. */
private val ClaimState.Filed.calculation: Calculation?
    get() =
        when (this) {
            is ClaimState.AwaitingReview -> calculation
            is ClaimState.Approved -> calculation
            is ClaimState.PaidOut -> calculation
            is ClaimState.Received, is ClaimState.Rejected -> null
        }
