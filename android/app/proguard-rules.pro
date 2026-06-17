# Flutter wraps its own engine classes; keep them so R8 does not strip the
# entry points the embedding looks up by reflection.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Keep Play Core split-install stubs referenced by the Flutter embedding even
# when the app does not ship deferred components. Prevents R8 "missing class"
# build failures on release.
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**
