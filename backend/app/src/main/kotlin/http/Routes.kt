package io.github.nikolaiht.forsinket.app.http

import arrow.core.Either
import arrow.core.left
import arrow.core.raise.either
import arrow.core.right
import io.github.nikolaiht.forsinket.app.ApiError
import io.github.nikolaiht.forsinket.app.ClaimService
import io.github.nikolaiht.forsinket.app.json.ClaimRequestDto
import io.github.nikolaiht.forsinket.app.json.DecisionRequestDto
import io.github.nikolaiht.forsinket.app.json.PayoutRequestDto
import io.github.nikolaiht.forsinket.app.json.toDraft
import io.github.nikolaiht.forsinket.app.json.toDto
import io.github.nikolaiht.forsinket.domain.ClaimId
import io.github.nikolaiht.forsinket.domain.StatusName
import io.github.nikolaiht.forsinket.domain.wireName
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationCall
import io.ktor.server.request.receive
import io.ktor.server.response.header
import io.ktor.server.response.respond
import io.ktor.server.routing.Route
import io.ktor.server.routing.get
import io.ktor.server.routing.post
import io.ktor.server.routing.route
import java.time.LocalDate
import java.time.format.DateTimeParseException
import java.util.UUID

/**
 * The API, under `/api`. Each handler reads the request, hands it to the
 * service, and turns what comes back into a response. No rule about claims
 * lives here, and nothing here knows what time it is.
 */
fun Route.api(service: ClaimService) {
    get("/rules") {
        call.respond(service.rules.toDto())
    }

    get("/examples") {
        call.respond(service.examples().map { it.toDto() })
    }

    get("/departures") {
        call.respondOr(call.dateParameter("date")) { date ->
            call.respond(service.departures(date).map { it.toDto() })
        }
    }

    post("/assessments") {
        val request = call.receive<ClaimRequestDto>()
        call.respondOr(service.preview(request.toDraft())) { assessment ->
            call.respond(assessment.toDto())
        }
    }

    route("/claims") {
        get {
            call.respondOr(call.statusParameter("status")) { status ->
                call.respond(service.list(status).map { it.toDto() })
            }
        }

        post {
            val request = call.receive<ClaimRequestDto>()
            call.respondOr(service.submit(request.toDraft())) { claim ->
                call.response.header(HttpHeaders.Location, "/api/claims/${claim.id.value}")
                call.respond(HttpStatusCode.Created, claim.toDto())
            }
        }

        get("/{id}") {
            call.respondOr(either { service.get(call.claimId().bind()).bind() }) { claim ->
                call.respond(claim.toDto())
            }
        }

        post("/{id}/decision") {
            val request = call.receive<DecisionRequestDto>()
            val result = either {
                service.decide(call.claimId().bind(), request.expectedVersion, request.toDraft()).bind()
            }
            call.respondOr(result) { claim ->
                call.respond(claim.toDto())
            }
        }

        post("/{id}/payout") {
            val request = call.receive<PayoutRequestDto>()
            val result = either {
                service.recordPayout(call.claimId().bind(), request.expectedVersion).bind()
            }
            call.respondOr(result) { claim ->
                call.respond(claim.toDto())
            }
        }
    }
}

/** Responds with the error, or lets [onSuccess] respond with the value. */
private suspend inline fun <T> ApplicationCall.respondOr(result: Either<ApiError, T>, onSuccess: (T) -> Unit) {
    result.fold(ifLeft = { respondError(it) }, ifRight = { onSuccess(it) })
}

/** An id that is not a UUID cannot be the id of a claim, so it is simply not found. */
private fun ApplicationCall.claimId(): Either<ApiError, ClaimId> =
    try {
        ClaimId(UUID.fromString(parameters["id"])).right()
    } catch (_: IllegalArgumentException) {
        ApiError.NotFound.left()
    }

/** A date written exactly like `2026-11-20`, the way a departure id starts. */
private fun ApplicationCall.dateParameter(name: String): Either<ApiError, LocalDate> {
    val raw = request.queryParameters[name].orEmpty()
    val malformed = ApiError.MalformedRequest("Query parameter '$name' must be a date like 2026-11-20.")
    if (!ISO_DATE.matches(raw)) return malformed.left()
    return try {
        LocalDate.parse(raw).right()
    } catch (_: DateTimeParseException) {
        malformed.left()
    }
}

private val ISO_DATE = Regex("""\d{4}-\d{2}-\d{2}""")

/** No status means every status. */
private fun ApplicationCall.statusParameter(name: String): Either<ApiError, StatusName?> {
    val raw = request.queryParameters[name] ?: return null.right()
    return StatusName.entries.find { it.wireName == raw }?.right()
        ?: ApiError.MalformedRequest(
            "Query parameter '$name' must be one of: ${StatusName.entries.joinToString { it.wireName }}.",
        ).left()
}
