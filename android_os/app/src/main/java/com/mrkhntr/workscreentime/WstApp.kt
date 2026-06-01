package com.mrkhntr.workscreentime

import android.app.Application
import com.mrkhntr.workscreentime.core.JsCore
import com.mrkhntr.workscreentime.data.Stores

/// Process-wide holder for the shared JS brain and the on-disk stores. Both the
/// AccessibilityService and the UI run on the main thread of this process, so a
/// single (main-thread-confined) JsCore is shared safely.
class WstApp : Application() {
    val core: JsCore by lazy { JsCore(this) }
    val stores: Stores by lazy { Stores(this) }
}
