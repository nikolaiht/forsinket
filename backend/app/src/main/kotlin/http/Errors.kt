package io.github.nikolaiht.forsinket.app.http

import io.github.nikolaiht.forsinket.app.ApiError
import io.github.nikolaiht.forsinket.app.json.ErrorDto
import io.github.nikolaiht.forsinket.app.json.toDto
import io.github.nikolaiht.forsinket.domain.wireName
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.ApplicationCall
import io.ktor.server.response.respond

/** The one place an [ApiError] becomes HTTP. */
suspend fun ApplicationCall.respondError(error: ApiError) {
    respond(error.status, error.toDto())
}

private val ApiError.status: HttpStatusCode
    get() =
        when (this) {
            ApiError.NotFound -> HttpStatusCode.NotFound
            is ApiError.Validation -> HttpStatusCode.UnprocessableEntity
            is ApiError.VersionConflict -> HttpStatusCode.Conflict
            is ApiError.InvalidTransition -> HttpStatusCode.Conflict
            is ApiError.MalformedRequest -> HttpStatusCode.BadRequest
            ApiError.DemoLimitReached -> HttpStatusCode.TooManyRequests
        }

// The return type is the sealed ErrorDto, not the variant, which is what makes
// the serializer write the "type" field.
private fun ApiError.toDto(): ErrorDto =
    when (this) {
        ApiError.NotFound -> ErrorDto.NotFound
        is ApiError.Validation -> ErrorDto.Validation(errors.map { it.toDto() })
        is ApiError.VersionConflict -> ErrorDto.VersionConflict(currentVersion)
        is ApiError.InvalidTransition -> ErrorDto.InvalidTransition(status.wireName)
        is ApiError.MalformedRequest -> ErrorDto.MalformedRequest(detail)
        ApiError.DemoLimitReached -> ErrorDto.DemoLimitReached
    }
