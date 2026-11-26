package io.github.nikolaiht.forsinket.app.json

import io.github.nikolaiht.forsinket.domain.code
import kotlinx.serialization.json.Json

/**
 * The one JSON format, for the API and for stored events. A value that can
 * take several shapes carries a "type" field, absent values are written as
 * null rather than left out, and unknown fields in a request are an error.
 */
val AppJson: Json = Json {
    classDiscriminator = "type"
    encodeDefaults = true
    explicitNulls = true
    ignoreUnknownKeys = false
}

/**
 * Reads an enum from the lower-case name it is stored under. Only for data
 * this service wrote itself: a value it does not recognise there means the
 * data is corrupt. What comes from a client is checked by the domain instead.
 */
internal inline fun <reified E : Enum<E>> storedEnum(code: String): E =
    enumValues<E>().find { it.code == code }
        ?: error("corrupt stored data: '$code' is not a ${E::class.simpleName}")
