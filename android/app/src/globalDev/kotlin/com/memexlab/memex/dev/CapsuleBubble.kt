package com.memexlab.memex.dev

import android.app.Activity
import android.os.Bundle
import com.memexlab.memex.ChatBubble

/** Development launcher for testing the same bubble available in Settings. */
class CapsuleBubbleLauncherActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (ChatBubble.show(this, expand = true) == "notifications") {
            ChatBubble.openSettings(this, notifications = true)
        }
        finish()
    }
}
