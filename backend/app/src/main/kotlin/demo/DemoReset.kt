package io.github.nikolaiht.forsinket.app.demo

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlin.time.Duration

/**
 * Runs [reset] once every [interval], for as long as the caller lives.
 *
 * A reset that fails, because the database is away for a moment or for any
 * other reason, is handed to [onFailure] and the next one is still tried.
 * Without that, the first failure would end the loop quietly, and an open demo
 * would fill up and stay full until someone restarted it.
 */
suspend fun resetRepeatedly(interval: Duration, onFailure: (Exception) -> Unit, reset: suspend () -> Unit): Nothing {
    while (true) {
        delay(interval)
        try {
            reset()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            onFailure(e)
        }
    }
}
