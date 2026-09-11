# ProGuard & R8 rules for iTantra (SIH 26173)

# 1. Sherpa-ONNX Native JNI Bindings
-keep class com.k2fsa.sherpa.onnx.** { *; }
-dontwarn com.k2fsa.sherpa.onnx.**

# 2. ONNX Runtime Android
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# 3. Protocol Buffers Lite
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# 4. Flutter & Native Plugin Channels
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# 5. Audio and Media Players
-keep class xyz.luan.audioplayers.** { *; }
-keep class com.google.android.exoplayer2.** { *; }

# 6. SQLite native bindings
-keep class io.requery.android.database.sqlite.** { *; }
