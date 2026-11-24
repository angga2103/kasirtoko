# Proguard rules for ML Kit and dependencies
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_face.** { *; }
-keepclassmembers class * { @com.google.mlkit.** <methods>; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**
-dontwarn java.lang.invoke.**
-dontwarn com.google.errorprone.annotations.**
