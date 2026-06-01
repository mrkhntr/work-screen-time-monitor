package com.mrkhntr.workscreentime.notify

import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONObject
import java.io.IOException

/// Sends an already-rendered webhook request from the core's `sendWebhook`
/// effect. The core builds url/headers/body; native only performs the POST.
class WebhookSender {
    private val client = OkHttpClient()
    private val jsonType = "application/json".toMediaType()

    fun send(request: JSONObject) {
        val url = request.optString("url")
        if (!url.startsWith("http://") && !url.startsWith("https://")) return

        val body = request.optJSONObject("body") ?: JSONObject()
        val builder = Request.Builder().url(url).post(body.toString().toRequestBody(jsonType))

        request.optJSONObject("headers")?.let { headers ->
            val keys = headers.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                builder.header(key, headers.optString(key))
            }
        }

        runCatching {
            client.newCall(builder.build()).enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {}
                override fun onResponse(call: Call, response: Response) {
                    response.close()
                }
            })
        }
    }
}
