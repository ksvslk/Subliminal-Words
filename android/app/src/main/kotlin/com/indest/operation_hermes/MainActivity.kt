package com.indest.subliminalwords

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Native side of Stagenator claim-link handling (see the AI Movie Quiz app
 * for the same pattern). FCM notification taps deliver the data payload in
 * the launch intent's extras; the firebase_messaging plugin's delivery is
 * racy on engine boot and replays on task-root re-delivery. This class is
 * the source of truth for "has this message been handled": a persisted set
 * of consumed ids that both the native capture and the Dart plugin path
 * (via "consume") check before opening anything.
 */
class MainActivity : FlutterFragmentActivity() {
    private var pendingClaimUrl: String? = null
    private var channel: MethodChannel? = null

    private fun consumeOnce(messageId: String): Boolean {
        val prefs = getSharedPreferences("stagenator_claim", MODE_PRIVATE)
        val seen = prefs.getStringSet("consumed_ids", emptySet())!!.toMutableSet()
        if (!seen.add(messageId)) return false
        while (seen.size > 40) seen.remove(seen.first())
        prefs.edit().putStringSet("consumed_ids", seen).apply()
        return true
    }

    private fun captureClaimUrl(intent: Intent?) {
        val extras = intent?.extras ?: return
        val url = extras.getString("claimUrl") ?: return
        if (!url.startsWith("https://")) return
        val messageId = extras.getString("google.message_id")
            ?: extras.getString("google_message_id") ?: return
        if (consumeOnce(messageId)) pendingClaimUrl = url
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureClaimUrl(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureClaimUrl(intent)
        pendingClaimUrl?.let { url ->
            pendingClaimUrl = null // consumed by this active push
            channel?.invokeMethod("claimUrl", url)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "stagenator/claim"
        ).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPendingClaimUrl" -> {
                        result.success(pendingClaimUrl)
                        pendingClaimUrl = null
                    }
                    "consume" -> {
                        val id = call.arguments as? String
                        result.success(id != null && consumeOnce(id))
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
}
