package com.memexlab.memex

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/** Quick Settings tile "Conversar" (F15-06, D-068): opens the floating chat in type mode from any app. */
class ConversarTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        // A plain action, not a toggle: always inactive.
        qsTile?.apply {
            state = Tile.STATE_INACTIVE
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        // Locked device: unlock first, so the chat never opens over the lock screen.
        if (isLocked) unlockAndRun { openChat() } else openChat()
    }

    private fun openChat() {
        val intent = Intent(this, FloatingChatActivity::class.java)
            .putExtra(FloatingChatActivity.EXTRA_MODE, "type")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14+ only accepts a PendingIntent here; the Intent overload is deprecated.
            val pending = PendingIntent.getActivity(
                this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            startActivityAndCollapse(pending)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
