package com.thisisnsh.cuecard.android.services

import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class TakeStoreTest {
    @Test fun reopeningAndSwitchingScriptsPreservesTheirPreviousTakes() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val store = TakeStore.getInstance(instrumentation.targetContext)
        val first = UUID.randomUUID().toString()
        val second = UUID.randomUUID().toString()
        val previous = TeleprompterSession(1_000L, 2_000L)
        val other = TeleprompterSession(3_000L, 4_000L)
        instrumentation.runOnMainSync {
            try {
                store.recordSession(first, previous.start, previous.end)
                store.recordSession(second, other.start, other.end)
                store.setDetails(TakeDetails(tags = listOf("Keep"), note = "First take"), "video", first)

                store.begin(first)
                assertEquals(previous, store.sessions(first).first())
                assertEquals(2, store.sessions(first).size)
                store.end()
                assertEquals(previous, store.sessions(first).first())

                store.begin(first)
                assertEquals(3, store.sessions(first).size)
                store.begin(second)
                assertEquals(listOf(previous), store.sessions(first).take(1))
                assertEquals(3, store.sessions(first).size)
                assertEquals(other, store.sessions(second).first())
                assertEquals(2, store.sessions(second).size)
                assertEquals("First take", store.details(first)["video"]?.note)
            } finally {
                store.end()
                store.remove(first)
                store.remove(second)
            }
        }
    }
}
