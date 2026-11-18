# Ad / attribution SDKs (they also ship consumer rules; these are belt and braces).
-keep class com.facebook.** { *; }
-keep class com.tiktok.** { *; }
-keep class com.appsflyer.** { *; }
-keep class com.google.android.gms.ads.identifier.** { *; }
-keep class com.android.installreferrer.** { *; }
-dontwarn com.facebook.**
-dontwarn com.tiktok.**
-dontwarn com.appsflyer.**
