package io.github.nikolaiht.forsinket.app

import io.github.nikolaiht.forsinket.app.demo.seedDemoData
import io.github.nikolaiht.forsinket.app.http.module
import io.github.nikolaiht.forsinket.app.store.ClaimStore
import io.github.nikolaiht.forsinket.app.store.PostgresClaimStore
import io.github.nikolaiht.forsinket.app.store.dataSource
import io.github.nikolaiht.forsinket.app.store.migrate
import io.github.nikolaiht.forsinket.app.traffic.SyntheticTrafficData
import io.github.nikolaiht.forsinket.domain.ClaimId
import io.github.nikolaiht.forsinket.domain.RulesV1
import io.ktor.server.engine.embeddedServer
import io.ktor.server.netty.Netty
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import java.time.Clock
import java.util.UUID
import kotlin.system.exitProcess
import kotlin.time.Duration

/**
 * Where everything is put together. This is the only place that knows which
 * clock, which database and which traffic data the service runs on.
 */
fun main() {
    val config = configFrom(System.getenv()).fold(
        ifLeft = { problems ->
            problems.forEach { System.err.println("Configuration: $it") }
            exitProcess(1)
        },
        ifRight = { it },
    )

    val dataSource = dataSource(config.database.url, config.database.user, config.database.password)
    migrate(dataSource)

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

    if (config.demo != null) {
        runBlocking { seedDemoData(store, traffic, rules, clock.instant()) }
    }

    embeddedServer(Netty, port = config.port) {
        module(service, traffic, rules, clock, config.webRoot)

        config.demo?.resetEvery?.let { interval ->
            launch { resetEvery(interval, store) { seedDemoData(store, traffic, rules, clock.instant()) } }
        }
    }.start(wait = true)
}

/** Puts the open demo back to its seed data at a fixed interval, for as long as the server runs. */
private suspend fun resetEvery(interval: Duration, store: ClaimStore, seed: suspend () -> Unit) {
    while (true) {
        delay(interval)
        withContext(Dispatchers.IO) { store.reset() }
        seed()
    }
}
