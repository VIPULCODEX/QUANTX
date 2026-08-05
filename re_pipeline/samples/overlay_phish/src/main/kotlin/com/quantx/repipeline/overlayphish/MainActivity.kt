package com.quantx.repipeline.overlayphish

import android.content.Intent
import android.net.Uri
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
            text = "QuantX RE sample: overlay_phish\n\n" +
                "Lab-only TTP reproduction of an overlay-based phishing panel. " +
                "Grant 'draw over other apps' below, then start the overlay. " +
                "See ttp.json for ground truth."
        })
        layout.addView(Button(this).apply {
            text = "Grant Draw-Over-Other-Apps"
            setOnClickListener {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName"),
                    )
                )
            }
        })
        layout.addView(Button(this).apply {
            text = "Start Overlay"
            setOnClickListener {
                if (Settings.canDrawOverlays(this@MainActivity)) {
                    startService(Intent(this@MainActivity, PhishOverlayService::class.java))
                }
            }
        })
        setContentView(layout)
    }
}
