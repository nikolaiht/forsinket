package io.github.nikolaiht.forsinket.app.http

import io.github.nikolaiht.forsinket.app.ApiError
import io.github.nikolaiht.forsinket.app.ClaimService
import io.github.nikolaiht.forsinket.app.json.AppJson
import io.github.nikolaiht.forsinket.app.json.ErrorDto
import io.ktor.http.HttpStatusCode
import io.ktor.serialization.kotlinx.json.json
import io.ktor.server.application.Application
import io.ktor.server.application.install
import io.ktor.server.application.log
import io.ktor.server.http.content.singlePageApplication
import io.ktor.server.plugins.BadRequestException
import io.ktor.server.plugins.ContentTransformationException
import io.ktor.server.plugins.PayloadTooLargeException
import io.ktor.server.plugins.bodylimit.RequestBodyLimit
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.server.plugins.statuspages.StatusPages
import io.ktor.server.response.respond
import io.ktor.server.routing.get
import io.ktor.server.routing.route
import io.ktor.server.routing.routing
import java.nio.file.Path

/**
 * The HTTP application. Everything it needs is passed in, so a test can run
 * the same module with its own clock, ids and store.
 *
 * @param webRoot the directory with the built Elm app, or null to serve the API only
 */
fun Application.module(service: ClaimService, webRoot: Path?) {
    install(ContentNegotiation) {
        json(AppJson)
    }

    // No request this API takes comes near this size.
    install(RequestBodyLimit) {
        bodyLimit { MAX_REQUEST_BODY_BYTES }
    }

    // Exceptions become responses for two kinds of thing, neither of which the
    // domain could have returned as a value: the framework could not read a
    // request body (too large, not JSON, or not labelled as JSON), or there is
    // a bug or a broken database. The second kind is logged, and the response
    // says nothing about what went wrong inside.
    install(StatusPages) {
        exception<PayloadTooLargeException> { call, _ ->
            val body: ErrorDto = ErrorDto.MalformedRequest("The request body is too large.")
            call.respond(HttpStatusCode.PayloadTooLarge, body)
        }
        exception<BadRequestException> { call, _ ->
            call.respondError(ApiError.MalformedRequest(ErrorDto.UNREADABLE_BODY))
        }
        exception<ContentTransformationException> { call, _ ->
            call.respondError(ApiError.MalformedRequest(ErrorDto.UNREADABLE_BODY))
        }
        exception<Throwable> { call, cause ->
            call.application.log.error("Unhandled error", cause)
            val body: ErrorDto = ErrorDto.InternalError
            call.respond(HttpStatusCode.InternalServerError, body)
        }
    }

    routing {
        get("/health") {
            call.respond(mapOf("status" to "ok"))
        }

        route("/api") {
            api(service)

            // Anything else under /api is a mistake by a client, and must not
            // fall through to the web app below and come back as HTML.
            route("{...}") {
                handle { call.respondError(ApiError.NotFound) }
            }
        }

        if (webRoot != null) {
            // The Elm app does its own routing, so every other address gets index.html.
            singlePageApplication {
                filesPath = webRoot.toString()
            }
        }
    }
}

private const val MAX_REQUEST_BODY_BYTES = 64L * 1024
