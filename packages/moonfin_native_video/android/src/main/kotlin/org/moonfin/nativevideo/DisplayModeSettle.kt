package org.moonfin.nativevideo

/**
 * When a source start held for a display mode switch should run.
 *
 * The start waits until the display and the audio devices have been still for
 * [quietMs], so the HDMI renegotiation a switch sets off has landed before an
 * audio track opens. It never waits past [maxWaitMs] from [startedAtMs], since
 * a television that never settles must not keep playback from starting.
 *
 * The caller owns the clock, so the logic stays a plain object a JVM test can
 * drive.
 */
class DisplayModeSettle(
    private val quietMs: Long,
    maxWaitMs: Long,
    val startedAtMs: Long,
) {
    private val deadlineMs = startedAtMs + maxWaitMs

    /** How long from [nowMs] until the start runs, counted from the latest change. */
    fun delayAfterChange(nowMs: Long): Long =
        minOf(quietMs, (deadlineMs - nowMs).coerceAtLeast(0L))
}
