package io.github.nikolaiht.forsinket.app

import arrow.core.Either
import arrow.core.NonEmptyList
import arrow.core.left
import arrow.core.right
import io.github.nikolaiht.forsinket.app.store.ClaimStore
import io.github.nikolaiht.forsinket.app.store.VersionConflict
import io.github.nikolaiht.forsinket.domain.ClaimEvent
import io.github.nikolaiht.forsinket.domain.ClaimId
import io.github.nikolaiht.forsinket.domain.StatusName
import java.time.Instant

/** A store that keeps everything in memory, for tests of the service that need no database. */
class InMemoryClaimStore : ClaimStore {
    private val events = mutableMapOf<ClaimId, List<ClaimEvent>>()
    private val summaries = mutableMapOf<ClaimId, ClaimSummary>()
    private var lastReset: Instant? = null

    override fun load(id: ClaimId): List<ClaimEvent> = events[id].orEmpty()

    override fun append(
        id: ClaimId,
        expectedVersion: Int,
        events: NonEmptyList<ClaimEvent>,
        summary: ClaimSummary,
    ): Either<VersionConflict, Int> {
        val current = load(id)
        if (current.size != expectedVersion) return VersionConflict(current.size).left()
        this.events[id] = current + events
        summaries[id] = summary
        return (current.size + events.size).right()
    }

    override fun summaries(status: StatusName?): List<ClaimSummary> =
        summaries.values.filter { status == null || it.status == status }.sortedByDescending { it.submittedAt }

    override fun count(): Int = summaries.size

    override fun reset(now: Instant, notSince: Instant): Boolean {
        if (lastReset?.isAfter(notSince) == true) return false
        events.clear()
        summaries.clear()
        lastReset = now
        return true
    }
}
