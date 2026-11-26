package io.github.nikolaiht.forsinket.app.store

import arrow.core.Either
import arrow.core.NonEmptyList
import io.github.nikolaiht.forsinket.app.ClaimSummary
import io.github.nikolaiht.forsinket.domain.ClaimEvent
import io.github.nikolaiht.forsinket.domain.ClaimId
import io.github.nikolaiht.forsinket.domain.StatusName

/** The claim has moved on since the writer read it. [currentVersion] is where it is now. */
data class VersionConflict(val currentVersion: Int)

/**
 * Where claims are kept: an append-only log of events per claim, and a summary
 * of each claim for listing them. The calls block; the caller decides which
 * thread they run on.
 */
interface ClaimStore {
    /** Every event of a claim, oldest first. Empty for a claim that does not exist. */
    fun load(id: ClaimId): List<ClaimEvent>

    /**
     * Adds [events] to a claim that is at [expectedVersion], and stores
     * [summary] as its new summary, all or nothing. A claim that is at another
     * version, because someone else wrote first, is left untouched.
     *
     * @return the claim's new version
     */
    fun append(
        id: ClaimId,
        expectedVersion: Int,
        events: NonEmptyList<ClaimEvent>,
        summary: ClaimSummary,
    ): Either<VersionConflict, Int>

    /** Summaries, newest first. With a [status], only claims that have it. */
    fun summaries(status: StatusName?): List<ClaimSummary>

    fun count(): Int

    /** Removes every claim. For the demo, which starts over from its seed data. */
    fun reset()
}
