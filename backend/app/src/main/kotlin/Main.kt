package io.github.nikolaiht.forsinket.app

import arrow.core.getOrElse
import io.github.nikolaiht.forsinket.app.demo.prepareDemo
import io.github.nikolaiht.forsinket.app.demo.resetRepeatedly
import io.github.nikolaiht.forsinket.app.demo.startOverIfDue
import io.github.nikolaiht.forsinket.app.http.module
import io.github.nikolaiht.forsinket.app.store.PostgresClaimStore
import io.github.nikolaiht.forsinket.app.store.dataSource
import io.github.nikolaiht.forsinket.app.store.migrate
import io.github.nikolaiht.forsinket.app.traffic.SyntheticTrafficData
import io.github.nikolaiht.forsinket.domain.ClaimId
import io.github.nikolaiht.forsinket.domain.RulesV1
import io.ktor.server.application.log
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import java.lang.management.ManagementFactory
import java.time.Clock
import java.util.UUID
import kotlin.system.exitProcess
import kotlin.time.measureTime
import kotlin.time.measureTimedValue

/**
 * Where everything is put together. This is the only place that knows which
 * clock, which database and which traffic data the service runs on.
 */
fun main() {
    val config = configFrom(System.getenv()).getOrElse { problems ->
        problems.forEach { System.err.println("Configuration: $it") }
        exitProcess(1)
    }

    val (dataSource, connecting) = measureTimedValue {
        dataSource(config.database.url, config.database.user, config.database.password)
    }
    val migrating = measureTime { migrate(dataSource) }

    val store = PostgresClaimStore(dataSource)
    val clock = Clock.systemUTC()
    val traffic = SyntheticTrafficData
    val rules = RulesV1
    val service = ClaimService(
        store = store,
        traffic = traffic,
        rules = rules,
        clock = clock,
        newId = { ClaimId(UUID.randomUUID()) },
        maxClaims = config.demo?.maxClaims,
    )

    val preparingDemo = measureTime {
        config.demo?.let { demo ->
            runBlocking { prepareDemo(store, traffic, rules, clock.instant(), demo.resetEvery) }
        }
    }

    embeddedServer(Netty, port = config.port) {
        // This is how long a restart keeps a visitor waiting, so it is worth
        // knowing where the time goes.
        log.info(
            "Before serving: connecting to the database took $connecting, migrating $migrating, " +
                "the demo $preparingDemo. The JVM has been up for ${ManagementFactory.getRuntimeMXBean().uptime} ms.",
        )
        module(service, config.webRoot)

        config.demo?.resetEvery?.let { interval ->
            launch {
                resetRepeatedly(
                    interval,
                    onFailure = { log.error("Resetting the demo failed. It will be tried again.", it) },
                ) {
                    startOverIfDue(store, traffic, rules, clock.instant(), interval)
                }
            }
        }
    }.start(wait = true)
}
