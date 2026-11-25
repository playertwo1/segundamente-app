package com.memexlab.memex

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatBubbleTest {
    @Test
    fun `restores only when wanted and nothing is posted`() {
        assertTrue(ChatBubble.shouldRestore(true, "off"))
        assertFalse(ChatBubble.shouldRestore(false, "off"))
        assertFalse(ChatBubble.shouldRestore(true, "active"))
        assertFalse(ChatBubble.shouldRestore(true, "posted"))
        assertFalse(ChatBubble.shouldRestore(true, "notifications"))
    }
}
