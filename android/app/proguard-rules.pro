-keep class org.videolan.libvlc.** { *; }
-dontwarn org.videolan.libvlc.**

# WireGuard tunnel: the Go library calls back into these classes over JNI.
-keep class com.wireguard.android.backend.** { *; }
-keep class com.wireguard.crypto.** { *; }
-keep class com.wireguard.config.** { *; }
