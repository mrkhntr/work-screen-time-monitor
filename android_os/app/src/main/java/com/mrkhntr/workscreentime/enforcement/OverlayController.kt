package com.mrkhntr.workscreentime.enforcement

import android.content.Context
import android.graphics.PixelFormat
import android.view.WindowManager
import androidx.compose.ui.platform.ComposeView
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.lifecycle.setViewTreeViewModelStoreOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner

/// Shows/hides the full-screen block overlay (a ComposeView in a
/// TYPE_APPLICATION_OVERLAY window). Re-shown by the service whenever a blocked
/// app returns to the foreground.
class OverlayController(private val context: Context) {
    private val windowManager = context.getSystemService(WindowManager::class.java)
    private var view: ComposeView? = null
    private var owner: OverlayLifecycleOwner? = null

    fun show(state: BlockUiState, onSnooze: (String?) -> Unit, onDismiss: (String?) -> Unit) {
        hide()
        val lifecycleOwner = OverlayLifecycleOwner().also { it.onCreate() }
        val composeView = ComposeView(context).apply {
            setViewTreeLifecycleOwner(lifecycleOwner)
            setViewTreeViewModelStoreOwner(lifecycleOwner)
            setViewTreeSavedStateRegistryOwner(lifecycleOwner)
            setContent { BlockScreen(state, onSnooze, onDismiss) }
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT,
        )

        runCatching { windowManager.addView(composeView, params) }
        view = composeView
        owner = lifecycleOwner
    }

    fun hide() {
        view?.let { existing -> runCatching { windowManager.removeView(existing) } }
        view = null
        owner?.onDestroy()
        owner = null
    }

    val isShowing: Boolean get() = view != null
}
