package com.mrkhntr.workscreentime.data

import android.content.Context
import com.mrkhntr.workscreentime.core.JsCore
import java.io.File

/// Native persistence for the human-editable config and the core's opaque state
/// blob. Mirrors the macOS ConfigStore + state.json.
class Stores(context: Context) {
    private val configFile = File(context.filesDir, "config.json")
    private val stateFile = File(context.filesDir, "state.json")

    fun loadConfigJson(core: JsCore): String {
        if (configFile.exists()) return configFile.readText()
        val defaults = core.defaultConfig()
        configFile.writeText(defaults)
        return defaults
    }

    fun saveConfigJson(json: String) {
        configFile.writeText(json)
    }

    fun loadStateJson(core: JsCore): String {
        if (stateFile.exists()) return stateFile.readText()
        val defaults = core.defaultState()
        stateFile.writeText(defaults)
        return defaults
    }

    fun saveStateJson(json: String) {
        stateFile.writeText(json)
    }
}
