package io.github.nikolaiht.forsinket.domain

/**
 * An amount of money in whole øre.
 *
 * It is never negative. A negative amount would be a bug in the caller, not
 * something a passenger or an officer can cause, so it fails loudly instead of
 * being modelled as a value. The same goes for an amount too large to hold:
 * the arithmetic throws instead of wrapping around.
 */
@JvmInline
value class Money private constructor(val ore: Long) : Comparable<Money> {
    operator fun plus(other: Money): Money = Money(Math.addExact(ore, other.ore))

    /** [percent] of this amount, rounded to the nearest øre. */
    fun percent(percent: Int): Money {
        require(percent in 0..100) { "a percentage is between 0 and 100, was $percent" }
        return Money(roundHalfUp(Math.multiplyExact(ore, percent.toLong()), 100))
    }

    /** This amount split into [divisor] equal parts, rounded to the nearest øre. */
    fun dividedBy(divisor: Int): Money {
        require(divisor > 0) { "divisor must be positive, was $divisor" }
        return Money(roundHalfUp(ore, divisor.toLong()))
    }

    override fun compareTo(other: Money): Int = ore.compareTo(other.ore)

    override fun toString(): String = "${ore / 100},${(ore % 100).toString().padStart(2, '0')} kr"

    companion object {
        val ZERO = Money(0)

        fun ofOre(ore: Long): Money {
            require(ore >= 0) { "an amount must not be negative, was $ore øre" }
            return Money(ore)
        }

        fun ofKroner(kroner: Long): Money = ofOre(Math.multiplyExact(kroner, 100L))
    }
}

/**
 * The one rounding rule in the system: nearest whole øre, halves up. Every step
 * of a calculation that multiplies or divides goes through it, so the amount
 * shown for a step is exactly the amount the next step uses.
 */
private fun roundHalfUp(numerator: Long, denominator: Long): Long =
    Math.addExact(Math.multiplyExact(2L, numerator), denominator) / Math.multiplyExact(2L, denominator)
