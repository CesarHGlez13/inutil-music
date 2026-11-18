package com.inutilmusic.app

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * CAF session ownership follows audio_service's cached engine, not the visible
 * Activity. Home/Back and Activity recreation must not stop receiver progress
 * or queue-boundary delivery while the Dart relay/music handler still live.
 */
class InutilCastEnginePlugin : FlutterPlugin {
    private var sender: InutilCastPlugin? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        sender = InutilCastPlugin(binding.applicationContext, binding.binaryMessenger)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        sender?.dispose()
        sender = null
    }
}
