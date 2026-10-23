package org.moonfin.nativevideo

import org.junit.Assert.assertEquals
import org.junit.Test

class DisplayModeSettleTest {

    private val settle = DisplayModeSettle(quietMs = 1_500L, maxWaitMs = 7_000L, startedAtMs = 0L)

    @Test
    fun `a change pushes the start a full quiet period past it`() {
        assertEquals(1_500L, settle.delayAfterChange(nowMs = 0L))
        assertEquals(1_500L, settle.delayAfterChange(nowMs = 2_000L))
    }

    @Test
    fun `a change near the cap only waits until the cap`() {
        assertEquals(1_000L, settle.delayAfterChange(nowMs = 6_000L))
    }

    @Test
    fun `a change past the cap starts right away`() {
        assertEquals(0L, settle.delayAfterChange(nowMs = 9_000L))
    }
}
