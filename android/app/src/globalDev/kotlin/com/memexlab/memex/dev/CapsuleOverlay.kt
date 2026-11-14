package com.memexlab.memex.dev

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings

/**
 * Launcher entry "Cápsula: sobreposição" (dev only). Without the permission it opens the
 * "Aparecer sobre outros apps" screen; with it, it starts the overlay service. Tap again after granting.
 */
class CapsuleOverlayLauncherActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Settings.canDrawOverlays(this)) {
            CapsuleOverlayService.start(this)
        } else {
            CapsuleLog.event("overlay permission missing: opening settings")
            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
        }
        finish()
    }
}
