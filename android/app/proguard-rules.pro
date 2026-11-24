# Keep audio integration APIs that may be reached from Flutter plugins or
# Android framework entry points.
-keep class com.ryanheise.audioservice.** { *; }
-keep class com.inutilmusic.app.InutilCanvasEnginePlugin { *; }
-keep class com.inutilmusic.app.moment.InutilMomentExporterPlugin { *; }
