package com.quantx.repipeline.a11yreader

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

/**
 * Lab-only launcher for a QuantX agentic-RE research sample.
 *
 * Reproduces the enable-the-accessibility-service social-engineering step that
 * real banking trojans (Anatsa/Octo/Cerberus/Xenomorph) rely on, so the RE
 * pipeline has a realistic entry point to observe. This app performs no
 * malicious action — see ScreenReaderService and ttp.json for exactly what it
 * does and does not do.
 */
class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 96, 48, 48)
        }
        layout.addView(TextView(this).apply {
            text = "QuantX RE sample: a11y_screen_reader\n\n" +
                "Lab-only TTP reproduction. Enabling the accessibility service " +
                "below lets this app read on-screen text into a local log file " +
                "for research purposes only. See ttp.json for ground truth."
        })
        layout.addView(Button(this).apply {
            text = "Open Accessibility Settings"
            setOnClickListener {
                startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            }
        })
        setContentView(layout)
    }
}
