package io.github.nikolaiht.forsinket.app

import io.github.nikolaiht.forsinket.app.traffic.SyntheticTrafficData
import io.github.nikolaiht.forsinket.app.traffic.find
import io.github.nikolaiht.forsinket.domain.DepartureId
import io.github.nikolaiht.forsinket.domain.Outcome
import io.github.nikolaiht.forsinket.domain.dateIn2026
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.collections.shouldContainAll
import io.kotest.matchers.shouldBe
import io.kotest.property.Arb
import io.kotest.property.checkAll
import java.time.LocalDate
import java.time.LocalTime

class SyntheticTrafficDataTest : FunSpec({
    val friday = LocalDate.of(2026, 11, 20)

    test("a day has eight departures, in order of departure") {
        val departures = SyntheticTrafficData.departuresOn(friday)

        departures.map { it.trainNumber } shouldBe
            listOf("TB11", "TB12", "TB13", "TB14", "TB15", "TB16", "TB17", "TB18")
        departures.map { it.scheduledDeparture } shouldBe departures.map { it.scheduledDeparture }.sorted()
    }

    test("odd train numbers run from Fjordvik, even ones from Storhavn") {
        val departures = SyntheticTrafficData.departuresOn(friday)

        val tb11 = departures.first { it.trainNumber == "TB11" }
        val tb16 = departures.first { it.trainNumber == "TB16" }

        (tb11.origin to tb11.destination) shouldBe ("Fjordvik" to "Storhavn")
        (tb16.origin to tb16.destination) shouldBe ("Storhavn" to "Fjordvik")
    }

    test("the outcomes of 20 November 2026 are the ones the contract examples use") {
        val outcomes = SyntheticTrafficData.departuresOn(friday).associate { it.trainNumber to it.outcome }

        outcomes["TB14"] shouldBe Outcome.Ran(130)
        outcomes["TB16"] shouldBe Outcome.Ran(61)
        outcomes["TB17"] shouldBe Outcome.Ran(29)
    }

    test("the day after has a cancelled departure") {
        val saturday = SyntheticTrafficData.departuresOn(friday.plusDays(1))

        saturday.first { it.trainNumber == "TB15" }.outcome shouldBe Outcome.Cancelled
    }

    test("a departure is found by its id") {
        val found = SyntheticTrafficData.find(DepartureId("2026-11-20-TB16"))

        found?.date shouldBe friday
        found?.scheduledDeparture shouldBe LocalTime.of(16, 42)
        found?.outcome shouldBe Outcome.Ran(61)
    }

    test("an id that is not a departure is not found") {
        listOf(
            "garbage",
            "",
            "2026-11-20",
            "2026-11-20-XX99",
            "2026-13-45-TB11",
            "2026-11-20-TB16-extra",
        ).forEach { id ->
            SyntheticTrafficData.find(DepartureId(id)) shouldBe null
        }
    }

    test("the same date always gives the same departures, and every id leads back to its departure") {
        checkAll(Arb.dateIn2026()) { date ->
            val departures = SyntheticTrafficData.departuresOn(date)

            departures shouldBe SyntheticTrafficData.departuresOn(date)
            departures.forEach { SyntheticTrafficData.find(it.id) shouldBe it }
        }
    }

    test("a week of traffic has every kind of outcome the rules distinguish") {
        val delays = (0L..6L)
            .flatMap { SyntheticTrafficData.departuresOn(friday.plusDays(it)) }
            .map { it.outcome }

        delays shouldContainAll
            listOf(
                Outcome.Ran(0),
                Outcome.Ran(29),
                Outcome.Ran(30),
                Outcome.Ran(59),
                Outcome.Ran(60),
                Outcome.Ran(119),
                Outcome.Ran(120),
                Outcome.Cancelled,
            )
    }
})
