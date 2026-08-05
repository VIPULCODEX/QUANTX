package com.quantx.repipeline.a11yreader

import android.accessibilityservice.AccessibilityService
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.io.File

/**
 * TTP reproduction: "read the screen via AccessibilityService" — the primitive
 * every family in the Anatsa/Octo/Cerberus/Xenomorph lineage builds on.
 *
 * Ground truth (see ttp.json): walks the active window's node tree on every
 * content/state-change event and writes the extracted text to a LOCAL log file
 * under this app's own private storage. Nothing is transmitted anywhere. This
 * exists so the QuantX agentic-RE pipeline (re_pipeline/) has a known-behavior
 * sample to blindly rediscover — see the plan at
 * /home/vipul/.claude/plans/splendid-riding-cake.md, Part A.
 */
class ScreenReaderService : AccessibilityService() {

    private val logFile by lazy { File(filesDir, "screen_read_log.txt") }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val root = rootInActiveWindow ?: return
        val text = StringBuilder()
        collectText(root, text)
        if (text.isNotEmpty()) {
            logFile.appendText("[${System.currentTimeMillis()}] $text\n")
            Log.d(TAG, "read ${text.length} chars from active window (local log only)")
        }
        root.recycle()
    }

    private fun collectText(node: AccessibilityNodeInfo, out: StringBuilder) {
        node.text?.let { out.append(it).append(' ') }
        for (i in 0 until node.childCount) {
            node.getChild(i)?.let { child ->
                collectText(child, out)
                child.recycle()
            }
        }
    }

    override fun onInterrupt() {}

    companion object {
        private const val TAG = "ScreenReaderService"
    }
}
