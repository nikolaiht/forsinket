package io.github.nikolaiht.forsinket.app

import io.github.nikolaiht.forsinket.app.demo.resetRepeatedly
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runTest
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds

@OptIn(ExperimentalCoroutinesApi::class)
class DemoResetTest : FunSpec({
    test("the demo is reset once per interval") {
        runTest {
            var resets = 0
            val loop = launch { resetRepeatedly(60.minutes, onFailure = {}) { resets++ } }

            advanceTimeBy(59.minutes)
            resets shouldBe 0
            advanceTimeBy(2.minutes)
            resets shouldBe 1
            advanceTimeBy(120.minutes)
            resets shouldBe 3

            loop.cancel()
        }
    }

    test("a reset that fails is reported, and does not stop the resets after it") {
        runTest {
            var attempts = 0
            val failures = mutableListOf<String?>()
            val loop = launch {
                resetRepeatedly(1.minutes, onFailure = { failures += it.message }) {
                    attempts++
                    if (attempts == 1) error("the database is away")
                }
            }

            advanceTimeBy(3.minutes + 1.seconds)

            attempts shouldBe 3
            failures shouldBe listOf("the database is away")
            loop.cancel()
        }
    }
})
