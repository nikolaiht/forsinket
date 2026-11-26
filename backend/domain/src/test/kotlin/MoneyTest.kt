package io.github.nikolaiht.forsinket.domain

import io.kotest.assertions.throwables.shouldThrow
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.property.Arb
import io.kotest.property.arbitrary.int
import io.kotest.property.arbitrary.long
import io.kotest.property.checkAll
import java.math.BigDecimal
import java.math.RoundingMode

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

    test("percent and dividedBy agree with decimal arithmetic rounded half up") {
        checkAll(Arb.long(0L..2_000_000L), Arb.int(0..100), Arb.int(1..366)) { ore, percent, parts ->
            Money.ofOre(ore).percent(percent).ore shouldBe
                BigDecimal(ore).multiply(BigDecimal(percent)).divide(BigDecimal(100), 0, RoundingMode.HALF_UP).toLong()
            Money.ofOre(ore).dividedBy(parts).ore shouldBe
                BigDecimal(ore).divide(BigDecimal(parts), 0, RoundingMode.HALF_UP).toLong()
        }
    }

    test("a percentage is between 0 and 100") {
        shouldThrow<IllegalArgumentException> { Money.ofKroner(100).percent(101) }
        shouldThrow<IllegalArgumentException> { Money.ofKroner(100).percent(-1) }
    }

    test("an amount too large to hold fails loudly, and does not wrap around") {
        shouldThrow<ArithmeticException> { Money.ofOre(Long.MAX_VALUE) + Money.ofOre(1) }
        shouldThrow<ArithmeticException> { Money.ofKroner(Long.MAX_VALUE) }
        shouldThrow<ArithmeticException> { Money.ofOre(Long.MAX_VALUE).percent(50) }
    }
})
