package io.github.nikolaiht.forsinket.app

import io.github.nikolaiht.forsinket.app.json.AppJson
import io.github.nikolaiht.forsinket.app.json.StoredEvent
import io.github.nikolaiht.forsinket.app.json.toDomain
import io.github.nikolaiht.forsinket.app.json.toStored
import io.github.nikolaiht.forsinket.domain.claimEvent
import io.kotest.core.spec.style.FunSpec
import io.kotest.matchers.shouldBe
import io.kotest.property.Arb
import io.kotest.property.checkAll

class StoredEventPropertyTest : FunSpec({
    test("every event survives being written as JSON and read back") {
        checkAll(Arb.claimEvent()) { event ->
            val json = AppJson.encodeToString(StoredEvent.serializer(), event.toStored())

            AppJson.decodeFromString(StoredEvent.serializer(), json).toDomain() shouldBe event
        }
    }
})
