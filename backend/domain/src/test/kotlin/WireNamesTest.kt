package io.github.nikolaiht.forsinket.domain

import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe

/**
 * The names enum values go by outside the program, in the API and in stored
 * events, are derived from the names of the constants. That makes renaming a
 * constant a change to the API and to data already stored. This test lists
 * every name, so such a rename has to be made here too, on purpose.
 */
class WireNamesTest : FunSpec({
    fun names(values: List<Enum<*>>): List<String> = values.map { it.wireName }

    test("expense kinds") {
        names(ExpenseKind.entries) shouldBe listOf("taxi", "bus", "other")
    }

    test("reasons a claim is not eligible") {
        names(IneligibilityReason.entries) shouldBe listOf("submitted_too_late", "delay_below_threshold")
    }

    test("reasons for review") {
        names(ReviewReason.entries) shouldBe listOf("expenses_claimed", "above_auto_approval_limit")
    }

    test("reasons an officer can reject for") {
        names(RejectionReason.entries) shouldBe listOf("invalid_ticket", "duplicate_claim", "other")
    }

    test("statuses") {
        names(StatusName.entries) shouldBe listOf("received", "awaiting_review", "approved", "rejected", "paid_out")
    }

    test("validation error codes") {
        names(ErrorCode.entries) shouldBe
            listOf(
                "unknown_departure",
                "departure_in_future",
                "must_be_positive",
                "must_not_be_negative",
                "above_maximum",
                "unsupported_validity",
                "unknown_value",
                "required",
                "too_long",
                "invalid_format",
            )
    }
})
