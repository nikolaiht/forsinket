package io.github.nikolaiht.forsinket.app.traffic

import io.github.nikolaiht.forsinket.domain.Departure
import io.github.nikolaiht.forsinket.domain.DepartureId
import java.time.LocalDate
import java.time.format.DateTimeParseException

/**
 * The traffic system: what ran on a given day, and how late. In a real
 * operator this is another system, so the claims service only knows this port.
 */
fun interface TrafficData {
    fun departuresOn(date: LocalDate): List<Departure>
}

/** A departure id starts with its date, so the day to search is in the id itself. */
fun TrafficData.find(id: DepartureId): Departure? = dateOf(id)?.let { date -> departuresOn(date).find { it.id == id } }

private fun dateOf(id: DepartureId): LocalDate? =
    try {
        LocalDate.parse(id.value.take(ISO_DATE_LENGTH))
    } catch (_: DateTimeParseException) {
        null
    }

private const val ISO_DATE_LENGTH = 10
