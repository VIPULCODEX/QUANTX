package com.quantx.repipeline.a11ytap

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity

/**
 * Lab-only launcher and paired test target for the auto-tap RE sample.
 *
 * The button below is intentionally labeled with the exact marker string
 * AutoTapService looks for, so this app is both the harness and the only
 * possible target of its own automated tap — it can never fire against a
 * real app by accident.
 */
class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 96, 48, 48)
        }
        layout.addView(TextView(this).apply {
            text = "QuantX RE sample: a11y_auto_tap\n\n" +
                "Lab-only TTP reproduction of accessibility-driven auto-tap. " +
                "Enable the service, then watch the marked button below get " +
                "tapped automatically. See ttp.json for ground truth."
        })
        layout.addView(Button(this).apply {
            text = "Open Accessibility Settings"
            setOnClickListener { startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) }
        })
        layout.addView(Button(this).apply {
            text = "RE_SAMPLE_TARGET"
            setOnClickListener {
                Toast.makeText(this@MainActivity, "tapped", Toast.LENGTH_SHORT).show()
            }
        })
        setContentView(layout)
    }
}
