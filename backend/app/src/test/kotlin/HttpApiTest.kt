package io.github.nikolaiht.forsinket.app

import io.github.nikolaiht.forsinket.app.http.module
import io.github.nikolaiht.forsinket.app.json.AppJson
import io.github.nikolaiht.forsinket.app.store.ClaimStore
import io.github.nikolaiht.forsinket.app.store.PostgresClaimStore
import io.github.nikolaiht.forsinket.app.traffic.SyntheticTrafficData
import io.github.nikolaiht.forsinket.domain.ClaimEvent
import io.github.nikolaiht.forsinket.domain.ClaimId
import io.github.nikolaiht.forsinket.domain.RulesV1
import io.kotest.assertions.withClue
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.matchers.string.shouldContain
import io.kotest.matchers.string.shouldStartWith
import io.ktor.client.HttpClient
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.ByteArrayContent
import io.ktor.http.contentType
import io.ktor.server.testing.runTestApplication
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.nio.file.Files
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.UUID

/** A clock the test sets, so that what the service records is known in advance. */
class TestClock(var now: Instant) : Clock() {
    override fun instant(): Instant = now

    override fun getZone(): ZoneId = ZoneOffset.UTC

    override fun withZone(zone: ZoneId): Clock = this
}

private class Api(private val client: HttpClient, val clock: TestClock) {
    suspend fun get(path: String): HttpResponse = client.get(path)

    suspend fun post(path: String, body: String): HttpResponse =
        client.post(path) {
            contentType(ContentType.Application.Json)
            setBody(body)
        }

    /** Posts [body] labelled as [type], or with no content type at all. */
    suspend fun postAs(type: ContentType?, path: String, body: String): HttpResponse =
        client.post(path) {
            type?.let { contentType(it) }
            setBody(ByteArrayContent(body.toByteArray(), contentType = type))
        }

    /** Posts one of the request examples from the contract. */
    suspend fun postExample(path: String, example: String): HttpResponse =
        post(path, contractExample(example).toString())
}

private suspend fun HttpResponse.json(): JsonElement = AppJson.parseToJsonElement(bodyAsText())

private fun JsonElement.field(name: String): JsonElement = jsonObject.getValue(name)

private val JsonElement.type: String
    get() = field("type").jsonPrimitive.content

/**
 * The whole service over HTTP, against a real PostgreSQL: routing, JSON,
 * validation, the decider, the store and the error mapping together. The
 * bodies are compared with the same contract examples the Elm tests decode.
 */
class HttpApiTest : FunSpec({
    val store = PostgresClaimStore(PostgresTestDatabase.dataSource)
    val fixtures = ContractFixtures
    val webRoot = Files.createTempDirectory("forsinket-web").also { directory ->
        Files.writeString(directory.resolve("index.html"), "<!doctype html><title>forsinket</title>")
        Files.writeString(directory.resolve("style.css"), "body { margin: 0 }")
    }

    beforeTest { store.reset() }

    /** Runs [test] against a fresh service whose new claims get [ids], in order. */
    suspend fun withApi(ids: List<ClaimId> = emptyList(), maxClaims: Int? = null, test: suspend Api.() -> Unit) {
        val clock = TestClock(fixtures.submittedA)
        val remainingIds = ArrayDeque(ids)
        val service = ClaimService(
            store = store,
            traffic = SyntheticTrafficData,
            rules = RulesV1,
            clock = clock,
            newId = { remainingIds.removeFirstOrNull() ?: ClaimId(UUID.randomUUID()) },
            maxClaims = maxClaims,
        )
        runTestApplication {
            application { module(service, webRoot) }
            Api(client, clock).test()
        }
    }

    context("the life of a claim") {
        test("a claim with expenses goes to an officer, is approved, and is paid out") {
            withApi(listOf(fixtures.idB)) {
                clock.now = fixtures.submittedB
                val submitted = postExample("/api/claims", "claim-request.period-with-expenses.json")

                submitted.status shouldBe HttpStatusCode.Created
                submitted.headers[HttpHeaders.Location] shouldBe "/api/claims/${fixtures.idB.value}"
                submitted.json() shouldBe contractExample("claim.awaiting-review.json")

                clock.now = fixtures.decidedAt
                val decided = postExample("/api/claims/${fixtures.idB.value}/decision", "decision-request.approve.json")

                decided.status shouldBe HttpStatusCode.OK
                decided.json() shouldBe contractExample("claim.approved-by-officer.json")

                clock.now = fixtures.paidAt
                val paid = post("/api/claims/${fixtures.idB.value}/payout", """{"expectedVersion":3}""")

                paid.status shouldBe HttpStatusCode.OK
                paid.json().field("status").type shouldBe "paid_out"
                paid.json().field("version") shouldBe JsonPrimitive(4)

                get("/api/claims/${fixtures.idB.value}").json() shouldBe paid.json()
            }
        }

        test("a claim the rules can settle is approved when it is submitted") {
            withApi(listOf(fixtures.idA)) {
                val submitted = postExample("/api/claims", "claim-request.single.json")

                submitted.status shouldBe HttpStatusCode.Created
                submitted.json() shouldBe contractExample("claim.approved-automatically.json")

                clock.now = fixtures.paidAt
                val paid = postExample("/api/claims/${fixtures.idA.value}/payout", "payout-request.json")

                paid.json() shouldBe contractExample("claim.paid-out.json")
            }
        }

        test("an officer can reject a claim") {
            withApi(listOf(fixtures.idB)) {
                clock.now = fixtures.submittedB
                postExample("/api/claims", "claim-request.period-with-expenses.json")

                clock.now = fixtures.decidedAt
                val rejected = postExample("/api/claims/${fixtures.idB.value}/decision", "decision-request.reject.json")

                rejected.json() shouldBe contractExample("claim.rejected-by-officer.json")
            }
        }

        test("a delay under the threshold is rejected by the rules, and still recorded") {
            withApi(listOf(fixtures.idC)) {
                clock.now = fixtures.submittedC
                val body =
                    """{"departureId":"2026-11-20-TB17","ticket":{"type":"single","price":34900},"expenses":null}"""

                val submitted = post("/api/claims", body)

                submitted.status shouldBe HttpStatusCode.Created
                submitted.json() shouldBe contractExample("claim.rejected-by-rules.json")
            }
        }

        test("the time recorded is cut to whole milliseconds") {
            withApi {
                clock.now = Instant.parse("2026-11-21T09:15:00.123456789Z")

                val submitted = postExample("/api/claims", "claim-request.single.json")

                submitted.json().field("submittedAt") shouldBe JsonPrimitive("2026-11-21T09:15:00.123Z")
            }
        }
    }

    context("assessments") {
        test("say what the rules would do, and store nothing") {
            withApi {
                postExample("/api/assessments", "claim-request.single.json").json() shouldBe
                    contractExample("assessment.auto-approve.json")
                postExample("/api/assessments", "claim-request.period-with-expenses.json").json() shouldBe
                    contractExample("assessment.manual-review.json")
                post(
                    "/api/assessments",
                    """{"departureId":"2026-11-20-TB17","ticket":{"type":"single","price":34900}}""",
                ).json() shouldBe contractExample("assessment.not-eligible.json")

                store.count() shouldBe 0
            }
        }

        test("are validated like claims") {
            withApi {
                val response = post(
                    "/api/assessments",
                    """{"departureId":"nope","ticket":{"type":"single","price":0}}""",
                )

                response.status shouldBe HttpStatusCode.UnprocessableEntity
                response.json().type shouldBe "validation"
            }
        }
    }

    context("what a client can get wrong") {
        test("values that are not acceptable are all reported, by field") {
            withApi {
                val body =
                    """
                    {"departureId":"nope",
                     "ticket":{"type":"period","price":0,"validityDays":14},
                     "expenses":{"amount":100,"kind":"boat"}}
                    """.trimIndent()

                val response = post("/api/claims", body)

                response.status shouldBe HttpStatusCode.UnprocessableEntity
                response.json() shouldBe contractExample("error.validation.json")
                store.count() shouldBe 0
            }
        }

        test("a body that cannot be read is a malformed request") {
            withApi {
                listOf(
                    "this is not json",
                    """{"departureId":"2026-11-20-TB16"}""",
                    """{"departureId":"2026-11-20-TB16","ticket":{"type":"single","price":"abc"}}""",
                    """{"departureId":"2026-11-20-TB16","ticket":{"type":"single","price":true}}""",
                    """{"departureId":"2026-11-20-TB16","ticket":{"type":"single","price":null}}""",
                    """{"departureId":"2026-11-20-TB16","ticket":{"type":"single","price":[34900]}}""",
                    """{"departureId":20261120,"ticket":{"type":"single","price":34900},"expenses":"none"}""",
                    """{"departureId":"2026-11-20-TB16","ticket":{"type":"weekly","price":34900}}""",
                    """{"departureId":"2026-11-20-TB16","ticket":{"type":"single","price":34900},"extra":true}""",
                    """{"departureId":"2026-11-20-TB16","ticket":{"type":"single","price":349.5}}""",
                ).forEach { body ->
                    withClue(body) {
                        val response = post("/api/claims", body)

                        response.status shouldBe HttpStatusCode.BadRequest
                        response.json() shouldBe contractExample("error.malformed-request.json")
                    }
                }
            }
        }

        test("a body that is not sent as JSON is a malformed request, not a server error") {
            withApi {
                listOf(ContentType.Text.Plain, ContentType.Application.FormUrlEncoded, null).forEach { type ->
                    withClue(type.toString()) {
                        val response =
                            postAs(type, "/api/claims", contractExample("claim-request.single.json").toString())

                        response.status shouldBe HttpStatusCode.BadRequest
                        response.json() shouldBe contractExample("error.malformed-request.json")
                    }
                }
                store.count() shouldBe 0
            }
        }

        test("a note with a character the database cannot store is a validation error, not a server error") {
            withApi(listOf(fixtures.idB)) {
                postExample("/api/claims", "claim-request.period-with-expenses.json")
                val withNul =
                    """{"expectedVersion":2,"officer":"KN","note":"a\u0000b","decision":{"type":"approve","approvedExpenses":0}}"""

                val response = post("/api/claims/${fixtures.idB.value}/decision", withNul)

                response.status shouldBe HttpStatusCode.UnprocessableEntity
                response.json().field("errors").jsonArray.map { it.field("field").jsonPrimitive.content } shouldBe
                    listOf("note")
            }
        }

        test("a body far larger than any request this API takes is turned away unread") {
            withApi {
                val huge = """{"departureId":"${"x".repeat(100_000)}","ticket":{"type":"single","price":34900}}"""

                val response = post("/api/claims", huge)

                response.status shouldBe HttpStatusCode.PayloadTooLarge
                response.json().type shouldBe "malformed_request"
            }
        }

        test("a whole number in quotes is read as the number") {
            // kotlinx.serialization does this even in its strict mode. It is
            // harmless, so it is pinned here instead of worked around.
            withApi {
                val body = """{"departureId":"2026-11-20-TB16","ticket":{"type":"single","price":"34900"}}"""

                val response = post("/api/claims", body)

                response.status shouldBe HttpStatusCode.Created
                response.json().field("ticket").field("price") shouldBe JsonPrimitive(34900)
            }
        }

        test("a claim that does not exist is not found") {
            withApi {
                listOf(
                    get("/api/claims/${UUID.randomUUID()}"),
                    get("/api/claims/not-a-uuid"),
                    post("/api/claims/${UUID.randomUUID()}/payout", """{"expectedVersion":2}"""),
                    post("/api/claims/${UUID.randomUUID()}/payout", """{"expectedVersion":0}"""),
                    postExample("/api/claims/${UUID.randomUUID()}/decision", "decision-request.approve.json"),
                ).forEach { response ->
                    response.status shouldBe HttpStatusCode.NotFound
                    response.json() shouldBe contractExample("error.not-found.json")
                }
            }
        }

        test("a path the API does not have is a JSON 404, not the web page") {
            withApi {
                val response = get("/api/nope")

                response.status shouldBe HttpStatusCode.NotFound
                response.json() shouldBe contractExample("error.not-found.json")
            }
        }

        test("deciding on a version someone else has already changed is a conflict") {
            withApi(listOf(fixtures.idB)) {
                postExample("/api/claims", "claim-request.period-with-expenses.json")
                postExample("/api/claims/${fixtures.idB.value}/decision", "decision-request.approve.json")

                // A second officer, still looking at version 2.
                val late = postExample("/api/claims/${fixtures.idB.value}/decision", "decision-request.reject.json")

                late.status shouldBe HttpStatusCode.Conflict
                late.json() shouldBe contractExample("error.version-conflict.json")
            }
        }

        test("deciding a claim that is already approved is an invalid transition") {
            withApi(listOf(fixtures.idA)) {
                postExample("/api/claims", "claim-request.single.json")

                val response =
                    postExample("/api/claims/${fixtures.idA.value}/decision", "decision-request.approve.json")

                response.status shouldBe HttpStatusCode.Conflict
                response.json() shouldBe contractExample("error.invalid-transition.json")
            }
        }

        test("an officer who covers more than the rules allow is told which field is wrong") {
            withApi(listOf(fixtures.idB)) {
                postExample("/api/claims", "claim-request.period-with-expenses.json")
                val tooMuch =
                    """{"expectedVersion":2,"officer":"KN","note":"","decision":{"type":"approve","approvedExpenses":62001}}"""

                val response = post("/api/claims/${fixtures.idB.value}/decision", tooMuch)

                response.status shouldBe HttpStatusCode.UnprocessableEntity
                response.json().field("errors") shouldBe
                    JsonArray(
                        listOf(
                            JsonObject(
                                mapOf(
                                    "field" to JsonPrimitive("decision.approvedExpenses"),
                                    "code" to JsonPrimitive("above_maximum"),
                                ),
                            ),
                        ),
                    )
            }
        }

        test("a decision is validated before the claim is touched") {
            withApi(listOf(fixtures.idB)) {
                postExample("/api/claims", "claim-request.period-with-expenses.json")
                val unsigned =
                    """{"expectedVersion":2,"officer":"","note":"","decision":{"type":"reject","reason":"nope"}}"""

                val response = post("/api/claims/${fixtures.idB.value}/decision", unsigned)

                response.status shouldBe HttpStatusCode.UnprocessableEntity
                response.json().field("errors").jsonArray.map { it.field("field").jsonPrimitive.content } shouldBe
                    listOf("officer", "note", "decision.reason")
            }
        }

        test("the open demo stops taking claims at its cap") {
            withApi(maxClaims = 1) {
                postExample("/api/claims", "claim-request.single.json").status shouldBe HttpStatusCode.Created

                val second = postExample("/api/claims", "claim-request.single.json")

                second.status shouldBe HttpStatusCode.TooManyRequests
                second.json() shouldBe contractExample("error.demo-limit-reached.json")
                store.count() shouldBe 1
            }
        }
    }

    context("listing claims") {
        test("newest first, and by status") {
            withApi(listOf(fixtures.idA, fixtures.idB, fixtures.idC)) {
                clock.now = fixtures.submittedA
                postExample("/api/claims", "claim-request.single.json")
                clock.now = fixtures.submittedB
                postExample("/api/claims", "claim-request.period-with-expenses.json")
                clock.now = fixtures.submittedC
                post("/api/claims", """{"departureId":"2026-11-20-TB17","ticket":{"type":"single","price":34900}}""")

                get("/api/claims").json() shouldBe contractExample("claims.summaries.json")
                val waiting = get("/api/claims?status=awaiting_review").json().jsonArray
                waiting.map { it.field("id").jsonPrimitive.content } shouldBe listOf(fixtures.idB.value.toString())
                get("/api/claims?status=paid_out").json() shouldBe JsonArray(emptyList())
            }
        }

        test("a status that does not exist is a malformed request") {
            withApi {
                val response = get("/api/claims?status=nope")

                response.status shouldBe HttpStatusCode.BadRequest
                response.json().type shouldBe "malformed_request"
            }
        }
    }

    context("reference data") {
        test("the rule set") {
            withApi { get("/api/rules").json() shouldBe contractExample("rules.json") }
        }

        test("the worked examples for the front page") {
            withApi { get("/api/examples").json() shouldBe contractExample("examples.json") }
        }

        test("a day's departures") {
            withApi { get("/api/departures?date=2026-11-20").json() shouldBe contractExample("departures.json") }
        }

        test("today's departures are listed, tomorrow's are not") {
            withApi {
                clock.now = Instant.parse("2026-11-20T22:30:00Z") // 23:30 in Oslo, still the 20th

                get("/api/departures?date=2026-11-20").json().jsonArray.size shouldBe 8
                get("/api/departures?date=2026-11-21").json() shouldBe JsonArray(emptyList())
            }
        }

        test("a departure is listed once it was due to leave, not before") {
            withApi {
                clock.now = Instant.parse("2026-11-20T12:00:00Z") // 13:00 in Oslo

                val departures = get("/api/departures?date=2026-11-20").json().jsonArray
                departures.map { it.field("trainNumber").jsonPrimitive.content } shouldBe
                    listOf("TB11", "TB12", "TB13", "TB14")
            }
        }

        test("a claim for a train that has not left yet is turned down") {
            withApi {
                clock.now = Instant.parse("2026-11-20T12:00:00Z") // 13:00 in Oslo, TB16 leaves at 16:42

                val response = postExample("/api/claims", "claim-request.single.json")

                response.status shouldBe HttpStatusCode.UnprocessableEntity
                response.json().field("errors").jsonArray.map { it.field("code").jsonPrimitive.content } shouldBe
                    listOf("departure_in_future")
            }
        }

        test("a missing or unreadable date is a malformed request") {
            withApi {
                listOf(
                    "/api/departures",
                    "/api/departures?date=20.11.2026",
                    "/api/departures?date=",
                    "/api/departures?date=-999999999-01-01",
                    "/api/departures?date=2026-W47-1",
                ).forEach { path ->
                    val response = get(path)

                    response.status shouldBe HttpStatusCode.BadRequest
                    response.json().type shouldBe "malformed_request"
                }
            }
        }
    }

    context("the web app") {
        test("is served at the root") {
            withApi {
                val response = get("/")

                response.status shouldBe HttpStatusCode.OK
                response.bodyAsText() shouldContain "<title>forsinket</title>"
            }
        }

        test("is served for every page address, so a reload or a shared link works") {
            withApi {
                listOf(
                    "/krav/nytt",
                    "/krav/${UUID.randomUUID()}",
                    "/saksbehandling",
                    "/saksbehandling?status=alle",
                ).forEach { path ->
                    val response = get(path)

                    response.status shouldBe HttpStatusCode.OK
                    response.bodyAsText() shouldContain "<title>forsinket</title>"
                }
            }
        }

        test("its files are served as files") {
            withApi {
                val response = get("/style.css")

                response.bodyAsText() shouldBe "body { margin: 0 }"
                response.headers[HttpHeaders.ContentType].orEmpty() shouldStartWith "text/css"
            }
        }
    }

    test("a bug, or a database that is gone, answers with an error the app can read, and gives nothing away") {
        val broken = object : ClaimStore by InMemoryClaimStore() {
            override fun load(id: ClaimId): List<ClaimEvent> =
                throw IllegalStateException("connection refused: db:5432")
        }
        val service =
            ClaimService(broken, SyntheticTrafficData, RulesV1, TestClock(fixtures.submittedA), { fixtures.idA }, null)

        runTestApplication {
            application { module(service, webRoot) }

            val response = client.get("/api/claims/${fixtures.idA.value}")

            response.status shouldBe HttpStatusCode.InternalServerError
            response.json() shouldBe contractExample("error.internal-error.json")
        }
    }

    test("health") {
        withApi {
            get("/health").json() shouldBe JsonObject(mapOf("status" to JsonPrimitive("ok")))
        }
    }
})
