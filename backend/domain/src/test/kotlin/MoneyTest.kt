package io.github.nikolaiht.forsinket.domain

import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.longs.shouldBeInRange
import io.kotest.matchers.shouldBe
import io.kotest.property.Arb
import io.kotest.property.arbitrary.int
import io.kotest.property.arbitrary.long
import io.kotest.property.checkAll

class MoneyTest : FunSpec({
    test("percent rounds half up to whole øre") {
        Money.ofOre(34950).percent(25) shouldBe Money.ofOre(8738) // 8737,5
        Money.ofOre(1429).percent(50) shouldBe Money.ofOre(715) // 714,5
        Money.ofOre(34900).percent(50) shouldBe Money.ofOre(17450)
    }

    test("dividedBy rounds half up to whole øre") {
        Money.ofKroner(100).dividedBy(7) shouldBe Money.ofOre(1429) // 1428,57
        Money.ofKroner(849).dividedBy(30) shouldBe Money.ofOre(2830)
        Money.ofOre(1).dividedBy(2) shouldBe Money.ofOre(1) // 0,5
    }

    test("amounts add") {
        Money.ofOre(2830) + Money.ofOre(50000) shouldBe Money.ofOre(52830)
    }

    test("amounts compare by value") {
        (Money.ofKroner(800) < Money.ofKroner(1000)) shouldBe true
        minOf(Money.ofOre(62000), Money.ofKroner(800)) shouldBe Money.ofOre(62000)
    }

    test("a negative amount is a bug") {
        shouldThrow<IllegalArgumentException> { Money.ofOre(-1) }
    }

    test("percent of 0..100 never exceeds the amount and never goes below zero") {
        checkAll(Arb.long(0L..2_000_000L), Arb.int(0..100)) { ore, percent ->
            Money.ofOre(ore).percent(percent).ore shouldBeInRange 0L..ore
        }
    }
})
