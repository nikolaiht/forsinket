package io.github.nikolaiht.forsinket.domain

import arrow.core.nonEmptyListOf
import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import java.time.Instant
import java.time.LocalDateTime

class RulesTest : FunSpec({
    fun rulesWith(vararg bands: DelayBand) =
        RulesV1.copy(bands = nonEmptyListOf(bands.first(), *bands.drop(1).toTypedArray()))

    test("a rule set whose bands are out of order cannot be made") {
        shouldThrow<IllegalArgumentException> { rulesWith(DelayBand(60, 50), DelayBand(30, 25)) }
    }

    test("a rule set that pays less for a longer delay cannot be made") {
        shouldThrow<IllegalArgumentException> { rulesWith(DelayBand(30, 50), DelayBand(60, 25)) }
    }

    test("a rule set that pays more than the ticket is worth cannot be made") {
        shouldThrow<IllegalArgumentException> { rulesWith(DelayBand(30, 25), DelayBand(60, 101)) }
        shouldThrow<IllegalArgumentException> { rulesWith(DelayBand(30, -1)) }
    }

    test("a point in time is read as the clock showed in Oslo, summer and winter") {
        Instant.parse("2026-11-20T22:30:00Z").inOslo() shouldBe LocalDateTime.of(2026, 11, 20, 23, 30)
        Instant.parse("2026-07-01T22:30:00Z").inOslo() shouldBe LocalDateTime.of(2026, 7, 2, 0, 30)
    }
})
