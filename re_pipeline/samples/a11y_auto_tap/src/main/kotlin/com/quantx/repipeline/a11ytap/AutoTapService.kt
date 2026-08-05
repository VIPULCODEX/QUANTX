package com.quantx.repipeline.a11ytap

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * TTP reproduction: "drive taps through an app on the victim's behalf via
 * AccessibilityService.dispatchGesture" — the transaction-automation step used
 * after screen-reading in real banking-trojan chains.
 *
 * Ground truth (ttp.json): on seeing a node whose text/content-description
 * contains the literal marker "RE_SAMPLE_TARGET" — a string only this
 * harness's own MainActivity ever shows — it dispatches a single synthetic
 * tap gesture at that node's screen bounds and logs the action locally. No
 * real target app is touched.
 */
class AutoTapService : AccessibilityService() {

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val root = rootInActiveWindow ?: return
        findMarkedNode(root)?.let { node ->
            tap(node)
            node.recycle()
        }
        root.recycle()
    }

    private fun findMarkedNode(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val text = (node.text?.toString().orEmpty()) + (node.contentDescription?.toString().orEmpty())
        if (text.contains(MARKER)) return AccessibilityNodeInfo.obtain(node)
        for (i in 0 until node.childCount) {
            node.getChild(i)?.let { child ->
                val hit = findMarkedNode(child)
                child.recycle()
                if (hit != null) return hit
            }
        }
        return null
    }

    private fun tap(node: AccessibilityNodeInfo) {
        val bounds = Rect()
        node.getBoundsInScreen(bounds)
        val path = Path().apply { moveTo(bounds.centerX().toFloat(), bounds.centerY().toFloat()) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 50))
            .build()
        dispatchGesture(gesture, null, Handler(Looper.getMainLooper()))
        Log.d(TAG, "dispatched synthetic tap on marked node (local log only)")
    }

    override fun onInterrupt() {}

    companion object {
        private const val TAG = "AutoTapService"
        private const val MARKER = "RE_SAMPLE_TARGET"
    }
}
