package io.github.nikolaiht.forsinket.app.traffic

import io.github.nikolaiht.forsinket.domain.Departure
import io.github.nikolaiht.forsinket.domain.DepartureId
import io.github.nikolaiht.forsinket.domain.Outcome
import java.time.LocalDate
import java.time.LocalTime

/**
 * Made-up traffic for a made-up railway: Tindbanen, between Fjordvik and
 * Storhavn. The departures are a pure function of the date, so the demo has
 * fresh traffic on whatever day it runs, and a test can name a date and know
 * what happened on it.
 */
object SyntheticTrafficData : TrafficData {
    private data class Service(
        val trainNumber: String,
        val departs: LocalTime,
        val origin: String,
        val destination: String,
    )

    private const val FJORDVIK = "Fjordvik"
    private const val STORHAVN = "Storhavn"

    private val timetable = listOf(
        Service("TB11", LocalTime.of(6, 12), FJORDVIK, STORHAVN),
        Service("TB12", LocalTime.of(7, 42), STORHAVN, FJORDVIK),
        Service("TB13", LocalTime.of(9, 12), FJORDVIK, STORHAVN),
        Service("TB14", LocalTime.of(12, 12), STORHAVN, FJORDVIK),
        Service("TB15", LocalTime.of(15, 12), FJORDVIK, STORHAVN),
        Service("TB16", LocalTime.of(16, 42), STORHAVN, FJORDVIK),
        Service("TB17", LocalTime.of(18, 12), FJORDVIK, STORHAVN),
        Service("TB18", LocalTime.of(21, 12), STORHAVN, FJORDVIK),
    )

    private val cancelled: Int? = null

    /**
     * Minutes late for each service, one row per day in a seven-day cycle.
     * Between them the rows hit both sides of every limit in the rules:
     * 29 and 30, 59 and 60, 119 and 120.
     */
    private val delays: List<List<Int?>> = listOf(
        listOf(0, 4, 75, 0, 12, 35, 0, 2),
        listOf(3, 0, 0, 130, 0, 61, 29, 0),
        listOf(0, 45, 0, 0, cancelled, 0, 8, 119),
        listOf(12, 0, 30, 0, 0, 185, 0, 59),
        listOf(0, 60, 0, 22, 0, 0, 120, 0),
        listOf(0, 0, 5, 0, 90, 0, 0, cancelled),
        listOf(7, 0, 0, 33, 0, 0, 0, 0),
    )

    override fun departuresOn(date: LocalDate): List<Departure> {
        val day = delays[Math.floorMod(date.toEpochDay(), delays.size.toLong()).toInt()]
        return timetable.zip(day) { service, delayMinutes ->
            Departure(
                id = DepartureId("$date-${service.trainNumber}"),
                date = date,
                trainNumber = service.trainNumber,
                origin = service.origin,
                destination = service.destination,
                scheduledDeparture = service.departs,
                outcome = delayMinutes?.let(Outcome::Ran) ?: Outcome.Cancelled,
            )
        }
    }
}
