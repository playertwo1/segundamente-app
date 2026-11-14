package com.memexlab.memex.dev

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.Icon
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.TextView
import com.memexlab.memex.FloatingChatActivity
import com.memexlab.memex.R
import kotlin.math.hypot

/**
 * Prototype B (F15-07): a draggable head drawn over other apps. Tap opens the floating chat;
 * long press or dragging it to the bottom stops the service. Dev build only.
 */
class CapsuleOverlayService : Service() {

    companion object {
        const val ACTION_STOP = "com.memexlab.memex.dev.OVERLAY_STOP"
        private const val CHANNEL_ID = "f1507_overlay"
        private const val NOTIFICATION_ID = 1508
        private const val HEAD_DP = 56
        private const val LONG_PRESS_MS = 600L

        fun start(context: Context) {
            context.startForegroundService(Intent(context, CapsuleOverlayService::class.java))
        }
    }

    private var windowManager: WindowManager? = null
    private var head: View? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WindowManager::class.java)
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        addHead()
        CapsuleLog.event("overlay service started")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) stopSelf()
        return START_STICKY
    }

    override fun onDestroy() {
        head?.let { runCatching { windowManager?.removeView(it) } }
        head = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        CapsuleLog.event("overlay service stopped")
        super.onDestroy()
    }

    private fun addHead() {
        val density = resources.displayMetrics.density
        val view = TextView(this).apply {
            text = "SM"
            gravity = Gravity.CENTER
            setTextColor(Color.BLACK)
            textSize = 16f
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xFFE8A33D.toInt())
            }
            elevation = 8 * density
        }
        val params = WindowManager.LayoutParams(
            (HEAD_DP * density).toInt(),
            (HEAD_DP * density).toInt(),
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 0
            y = (200 * density).toInt()
        }
        val slop = ViewConfiguration.get(this).scaledTouchSlop
        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        var moved = false
        var longPressed = false
        val longPress = Runnable {
            longPressed = true
            CapsuleLog.event("overlay hidden: long press")
            stopSelf()
        }
        view.setOnTouchListener { v, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    startX = params.x
                    startY = params.y
                    moved = false
                    longPressed = false
                    v.postDelayed(longPress, LONG_PRESS_MS)
                }
                MotionEvent.ACTION_MOVE -> {
                    if (!moved && hypot(event.rawX - downX, event.rawY - downY) > slop) {
                        moved = true
                        v.removeCallbacks(longPress)
                    }
                    if (moved) {
                        params.x = startX + (event.rawX - downX).toInt()
                        params.y = startY + (event.rawY - downY).toInt()
                        windowManager?.updateViewLayout(v, params)
                    }
                }
                MotionEvent.ACTION_UP -> {
                    v.removeCallbacks(longPress)
                    when {
                        longPressed -> Unit
                        !moved -> openChat()
                        event.rawY > resources.displayMetrics.heightPixels * 0.8f -> {
                            CapsuleLog.event("overlay hidden: dragged to bottom")
                            stopSelf()
                        }
                        else -> Unit
                    }
                }
                MotionEvent.ACTION_CANCEL -> v.removeCallbacks(longPress)
                else -> return@setOnTouchListener false
            }
            true
        }
        windowManager?.addView(view, params)
        head = view
        CapsuleLog.event("overlay shown")
    }

    private fun openChat() {
        CapsuleLog.event("overlay tapped: opening chat")
        startActivity(
            Intent(this, FloatingChatActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                .putExtra(FloatingChatActivity.EXTRA_MODE, "type"),
        )
    }

    private fun buildNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Cápsula de sobreposição (teste)", NotificationManager.IMPORTANCE_LOW),
        )
        val stopIntent = PendingIntent.getService(
            this,
            NOTIFICATION_ID,
            Intent(this, CapsuleOverlayService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_todo_notification)
            .setContentTitle("Cápsula de sobreposição ativa")
            .setContentText("Toque na bolinha para conversar. Segure ou arraste até a base para esconder.")
            .setOngoing(true)
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, R.drawable.ic_quick_note),
                    "Parar",
                    stopIntent,
                ).build(),
            )
            .build()
    }
}
