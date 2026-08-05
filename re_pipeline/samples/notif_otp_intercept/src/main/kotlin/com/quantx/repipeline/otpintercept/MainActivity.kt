package com.quantx.repipeline.otpintercept

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 96, 48, 48)
        }
        layout.addView(TextView(this).apply {
            text = "QuantX RE sample: notif_otp_intercept\n\n" +
                "Lab-only TTP reproduction of notification-based OTP " +
                "interception. Enable notification access below, then send a " +
                "test notification containing a 4-8 digit number. See " +
                "ttp.json for ground truth."
        })
        layout.addView(Button(this).apply {
            text = "Open Notification Access Settings"
            setOnClickListener {
                startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
            }
        })
        setContentView(layout)
    }
}
