package com.example.billalert

import android.app.KeyguardManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth draws the phone's fingerprint prompt as a fragment, so the
// activity has to be a FragmentActivity. With a plain FlutterActivity the
// plugin refuses every prompt as "uiUnavailable" — the button would appear
// to do nothing on a real phone while every test still passed.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        wakeForUrgentAlert(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        wakeForUrgentAlert(intent)
    }

    override fun onStop() {
        super.onStop()
        // Only for the alert that woke the phone. Left on, BillAlert would sit
        // above the lock screen whenever it was the last app open.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        }
    }

    // An urgent due-date alert fills the screen by launching this activity
    // while the phone is locked (Android 14 and later; older phones get a
    // pop-up and never reach this). Wake the screen, and ask for the phone's
    // own unlock straight away, so what shows above the lock screen is the
    // unlock prompt and never the household's bill.
    private fun wakeForUrgentAlert(intent: Intent?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        // flutter_local_notifications' action for a notification that opens
        // the app, which a full-screen alert does.
        if (intent?.action != "SELECT_NOTIFICATION") return
        val keyguard = getSystemService(KeyguardManager::class.java) ?: return
        if (!keyguard.isKeyguardLocked) return
        setShowWhenLocked(true)
        setTurnScreenOn(true)
        keyguard.requestDismissKeyguard(this, null)
    }
}
