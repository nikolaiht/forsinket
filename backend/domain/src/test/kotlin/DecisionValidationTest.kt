package io.github.nikolaiht.forsinket.domain

import arrow.core.left
import arrow.core.nonEmptyListOf
import arrow.core.right
import io.github.nikolaiht.forsinket.domain.ErrorCode.INVALID_FORMAT
import io.github.nikolaiht.forsinket.domain.ErrorCode.MUST_NOT_BE_NEGATIVE
import io.github.nikolaiht.forsinket.domain.ErrorCode.REQUIRED
import io.github.nikolaiht.forsinket.domain.ErrorCode.TOO_LONG
import io.github.nikolaiht.forsinket.domain.ErrorCode.UNKNOWN_VALUE
import io.github.nikolaiht.forsinket.domain.Field.APPROVED_EXPENSES
import io.github.nikolaiht.forsinket.domain.Field.DECISION_REASON
import io.github.nikolaiht.forsinket.domain.Field.NOTE
import io.github.nikolaiht.forsinket.domain.Field.OFFICER
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import java.time.Instant

class DecisionValidationTest : FunSpec({
    val at = Instant.parse("2026-11-21T12:30:00Z")
    val approval = DecisionDraft(
        officer = "KN",
        note = "Kvitteringen viser 500 kr.",
        decision = DecisionChoiceDraft.Approve(50000),
    )
    val rejection = approval.copy(
        note = "Samme reise er allerede erstattet.",
        decision = DecisionChoiceDraft.Reject("duplicate_claim"),
    )

    fun errors(vararg errors: FieldError) = nonEmptyListOf(errors.first(), *errors.drop(1).toTypedArray()).left()

    test("a valid approval becomes a command") {
        validateDecision(approval, at) shouldBe
            ClaimCommand.Decide(
                OfficerDecision.Approve(Money.ofOre(50000)),
                officerId("KN"),
                note("Kvitteringen viser 500 kr."),
                at,
            ).right()
    }

    test("a valid rejection becomes a command") {
        validateDecision(rejection, at) shouldBe
            ClaimCommand.Decide(
                OfficerDecision.Reject(RejectionReason.DUPLICATE_CLAIM),
                officerId("KN"),
                note("Samme reise er allerede erstattet."),
                at,
            ).right()
    }

    test("the officer is identified by 2 to 10 letters") {
        listOf("KN", "åse", "ABCDEFGHIJ").forEach { officer ->
            validateDecision(approval.copy(officer = officer), at).shouldBeRight()
        }
        listOf("K", "KN1", "K N", "ABCDEFGHIJK").forEach { officer ->
            validateDecision(approval.copy(officer = officer), at) shouldBe
                errors(FieldError(OFFICER, INVALID_FORMAT))
        }
    }

    test("a missing officer is reported as missing") {
        validateDecision(approval.copy(officer = "  "), at) shouldBe errors(FieldError(OFFICER, REQUIRED))
    }

    test("surrounding whitespace is not part of the officer or the note") {
        validateDecision(approval.copy(officer = " KN ", note = "  ok  "), at).map { it.officer to it.note } shouldBe
            (officerId("KN") to note("ok")).right()
    }

    test("a note can be at most 500 characters") {
        validateDecision(approval.copy(note = "a".repeat(500)), at).shouldBeRight()
        validateDecision(approval.copy(note = "a".repeat(501)), at) shouldBe errors(FieldError(NOTE, TOO_LONG))
    }

    test("a note can have several lines") {
        validateDecision(approval.copy(note = "Første linje.\nAndre linje."), at).map { it.note } shouldBe
            note("Første linje.\nAndre linje.").right()
    }

    test("a note cannot have control characters, which no keyboard types and the database will not store") {
        listOf("a\u0000b", "bell\u0007", "escape\u001B[0m").forEach { text ->
            validateDecision(approval.copy(note = text), at) shouldBe errors(FieldError(NOTE, INVALID_FORMAT))
        }
    }

    test("approving needs no note") {
        validateDecision(approval.copy(note = ""), at).shouldBeRight()
    }

    test("rejecting needs a note that explains why") {
        validateDecision(rejection.copy(note = "   "), at) shouldBe errors(FieldError(NOTE, REQUIRED))
    }

    test("the rejection reason must be one the system knows") {
        validateDecision(rejection.copy(decision = DecisionChoiceDraft.Reject("nope")), at) shouldBe
            errors(FieldError(DECISION_REASON, UNKNOWN_VALUE))
    }

    test("approved expenses cannot be negative") {
        validateDecision(approval.copy(decision = DecisionChoiceDraft.Approve(-1)), at) shouldBe
            errors(FieldError(APPROVED_EXPENSES, MUST_NOT_BE_NEGATIVE))
        validateDecision(approval.copy(decision = DecisionChoiceDraft.Approve(0)), at).shouldBeRight()
    }

    test("every problem is reported at once, in field order") {
        val draft = DecisionDraft(officer = "K", note = "", decision = DecisionChoiceDraft.Reject("nope"))

        validateDecision(draft, at) shouldBe
            errors(
                FieldError(OFFICER, INVALID_FORMAT),
                FieldError(NOTE, REQUIRED),
                FieldError(DECISION_REASON, UNKNOWN_VALUE),
            )
    }
})
