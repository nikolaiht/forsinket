package io.github.nikolaiht.forsinket.app

import arrow.core.right
import io.github.nikolaiht.forsinket.app.json.AppJson
import io.github.nikolaiht.forsinket.app.json.ClaimRequestDto
import io.github.nikolaiht.forsinket.app.json.DecisionRequestDto
import io.github.nikolaiht.forsinket.app.json.ErrorDto
import io.github.nikolaiht.forsinket.app.json.PayoutRequestDto
import io.github.nikolaiht.forsinket.app.json.toDraft
import io.github.nikolaiht.forsinket.app.json.toDto
import io.github.nikolaiht.forsinket.app.traffic.SyntheticTrafficData
import io.github.nikolaiht.forsinket.domain.ClaimDetails
import io.github.nikolaiht.forsinket.domain.ClaimDraft
import io.github.nikolaiht.forsinket.domain.DecisionChoiceDraft
import io.github.nikolaiht.forsinket.domain.DecisionDraft
import io.github.nikolaiht.forsinket.domain.ErrorCode
import io.github.nikolaiht.forsinket.domain.ExpensesDraft
import io.github.nikolaiht.forsinket.domain.Field
import io.github.nikolaiht.forsinket.domain.FieldError
import io.github.nikolaiht.forsinket.domain.RulesV1
import io.github.nikolaiht.forsinket.domain.StatusName
import io.github.nikolaiht.forsinket.domain.TicketDraft
import io.github.nikolaiht.forsinket.domain.assess
import io.github.nikolaiht.forsinket.domain.validateClaim
import io.github.nikolaiht.forsinket.domain.wireName
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement

/**
 * The Kotlin half of the contract. What the service sends must equal the
 * hand-written examples in `contract/examples`, and what it receives must be
 * read the way those examples say. The Elm half is `frontend/tests/ContractTest.elm`.
 */
class ContractTest : FunSpec({
    val fixtures = ContractFixtures
    val submittedOn = fixtures.day.plusDays(1)

    infix fun JsonElement.shouldMatchExample(name: String) {
        this shouldBe contractExample(name)
    }

    context("responses") {
        test("the rule set") {
            AppJson.encodeToJsonElement(RulesV1.toDto()) shouldMatchExample "rules.json"
        }

        test("a day's departures") {
            val departures = SyntheticTrafficData.departuresOn(fixtures.day).map { it.toDto() }

            AppJson.encodeToJsonElement(departures) shouldMatchExample "departures.json"
        }

        test("assessments") {
            fun assessment(claim: ClaimDetails) =
                AppJson.encodeToJsonElement(assess(RulesV1, claim, submittedOn).toDto())

            assessment(fixtures.claimA) shouldMatchExample "assessment.auto-approve.json"
            assessment(fixtures.claimB) shouldMatchExample "assessment.manual-review.json"
            assessment(fixtures.claimC) shouldMatchExample "assessment.not-eligible.json"
        }

        listOf(
            "claim.approved-automatically.json" to fixtures.approvedAutomatically,
            "claim.awaiting-review.json" to fixtures.awaitingReview,
            "claim.approved-by-officer.json" to fixtures.approvedByOfficer,
            "claim.rejected-by-officer.json" to fixtures.rejectedByOfficer,
            "claim.rejected-by-rules.json" to fixtures.rejectedByRules,
            "claim.paid-out.json" to fixtures.paidOut,
        ).forEach { (example, snapshot) ->
            test(example) {
                AppJson.encodeToJsonElement(snapshot.toDto()) shouldMatchExample example
            }
        }

        test("the worked examples for the front page") {
            AppJson.encodeToJsonElement(examples(RulesV1).map { it.toDto() }) shouldMatchExample "examples.json"
        }

        test("claim summaries") {
            val summaries = listOf(fixtures.rejectedByRules, fixtures.awaitingReview, fixtures.approvedAutomatically)
                .map { summarize(it).toDto() }

            AppJson.encodeToJsonElement(summaries) shouldMatchExample "claims.summaries.json"
        }
    }

    context("requests") {
        fun claimRequest(name: String): ClaimDraft =
            AppJson.decodeFromJsonElement<ClaimRequestDto>(contractExample(name)).toDraft()

        test("a claim for a single ticket") {
            val draft = claimRequest("claim-request.single.json")

            draft shouldBe ClaimDraft("2026-11-20-TB16", TicketDraft.Single(34900), expenses = null)
            validateClaim(RulesV1, draft, fixtures.claimA.departure, submittedOn.atStartOfDay()) shouldBe
                fixtures.claimA.right()
        }

        test("a claim for a period ticket with expenses") {
            val draft = claimRequest("claim-request.period-with-expenses.json")

            draft shouldBe
                ClaimDraft("2026-11-20-TB14", TicketDraft.Period(84900, 30), ExpensesDraft(62000, "taxi"))
            validateClaim(RulesV1, draft, fixtures.claimB.departure, submittedOn.atStartOfDay()) shouldBe
                fixtures.claimB.right()
        }

        test("a claim without the expenses field means no expenses") {
            val body = """{"departureId":"2026-11-20-TB16","ticket":{"type":"single","price":34900}}"""

            AppJson.decodeFromString<ClaimRequestDto>(body).toDraft() shouldBe
                ClaimDraft("2026-11-20-TB16", TicketDraft.Single(34900), expenses = null)
        }

        test("an officer's approval") {
            val request = AppJson.decodeFromJsonElement<DecisionRequestDto>(
                contractExample("decision-request.approve.json"),
            )

            request.expectedVersion shouldBe 2
            request.toDraft() shouldBe
                DecisionDraft("KN", ContractFixtures.RECEIPT_NOTE, DecisionChoiceDraft.Approve(50000))
        }

        test("an officer's rejection") {
            val request = AppJson.decodeFromJsonElement<DecisionRequestDto>(
                contractExample("decision-request.reject.json"),
            )

            request.expectedVersion shouldBe 2
            request.toDraft() shouldBe
                DecisionDraft("KN", ContractFixtures.DUPLICATE_NOTE, DecisionChoiceDraft.Reject("duplicate_claim"))
        }

        test("a payout") {
            AppJson.decodeFromJsonElement<PayoutRequestDto>(contractExample("payout-request.json")) shouldBe
                PayoutRequestDto(expectedVersion = 2)
        }
    }

    context("errors") {
        fun error(dto: ErrorDto): JsonElement = AppJson.encodeToJsonElement(dto)

        test("validation errors name the field by its path in the request") {
            val errors = listOf(
                FieldError(Field.DEPARTURE_ID, ErrorCode.UNKNOWN_DEPARTURE),
                FieldError(Field.TICKET_PRICE, ErrorCode.MUST_BE_POSITIVE),
                FieldError(Field.TICKET_VALIDITY_DAYS, ErrorCode.UNSUPPORTED_VALIDITY),
                FieldError(Field.EXPENSES_KIND, ErrorCode.UNKNOWN_VALUE),
            )

            error(ErrorDto.Validation(errors.map { it.toDto() })) shouldMatchExample "error.validation.json"
        }

        test("the other errors") {
            error(ErrorDto.NotFound) shouldMatchExample "error.not-found.json"
            error(ErrorDto.VersionConflict(currentVersion = 3)) shouldMatchExample "error.version-conflict.json"
            error(ErrorDto.InvalidTransition(StatusName.APPROVED.wireName)) shouldMatchExample
                "error.invalid-transition.json"
            error(ErrorDto.MalformedRequest(ErrorDto.UNREADABLE_BODY)) shouldMatchExample
                "error.malformed-request.json"
            error(ErrorDto.DemoLimitReached) shouldMatchExample "error.demo-limit-reached.json"
            error(ErrorDto.InternalError) shouldMatchExample "error.internal-error.json"
        }
    }
})
