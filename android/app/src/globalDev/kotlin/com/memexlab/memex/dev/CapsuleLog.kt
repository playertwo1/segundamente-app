package com.memexlab.memex.dev

import android.util.Log

/** Dev-only measurement log for the F15-07 prototypes. Read with: adb logcat -v time -s F1507 */
object CapsuleLog {
    private const val TAG = "F1507"

    fun event(message: String) {
        Log.i(TAG, "${System.currentTimeMillis()} $message")
    }
}
