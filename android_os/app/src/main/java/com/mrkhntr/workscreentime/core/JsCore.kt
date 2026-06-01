package com.mrkhntr.workscreentime.core

import android.content.Context
import com.whl.quickjs.android.QuickJSLoader
import com.whl.quickjs.wrapper.JSFunction
import com.whl.quickjs.wrapper.QuickJSContext

/// Loads the shared TypeScript brain (`core.js` from assets) into QuickJS and
/// exposes its `WSTCore` JSON-string API. Confined to the caller's thread
/// (QuickJS contexts are not thread-safe); in this app that is the main thread.
class JsCore(context: Context) {
    private val ctx: QuickJSContext
    private val reduceFn: JSFunction
    private val defaultConfigFn: JSFunction
    private val normalizeConfigFn: JSFunction
    private val defaultStateFn: JSFunction

    init {
        QuickJSLoader.init()
        ctx = QuickJSContext.create()
        val source = context.assets.open("core.js").bufferedReader().use { it.readText() }
        ctx.evaluate(source)
        val wstCore = ctx.globalObject.getJSObject("WSTCore")
        reduceFn = wstCore.getJSFunction("reduce")
        defaultConfigFn = wstCore.getJSFunction("defaultConfig")
        normalizeConfigFn = wstCore.getJSFunction("normalizeConfig")
        defaultStateFn = wstCore.getJSFunction("defaultState")
    }

    @Synchronized
    fun reduce(state: String, event: String, now: String, config: String): String =
        reduceFn.call(state, event, now, config) as? String ?: "{}"

    @Synchronized
    fun defaultConfig(): String = defaultConfigFn.call() as? String ?: "{}"

    @Synchronized
    fun normalizeConfig(json: String): String = normalizeConfigFn.call(json) as? String ?: json

    @Synchronized
    fun defaultState(): String = defaultStateFn.call() as? String ?: "{}"
}
