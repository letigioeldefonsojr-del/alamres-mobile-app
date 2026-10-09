-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { <init>(); }
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
-dontwarn androidx.work.**
-dontwarn androidx.room.**

# --- Firebase / Google Play Services / Google Sign-In ---
# isMinifyEnabled is on for release builds (see build.gradle.kts), and
# `flutter build apk` builds release by default. Without these rules, R8
# strips/renames internal classes that Firebase Auth and Google Sign-In use
# (via reflection and Parcelable) to save and restore a signed-in session -
# this is what was silently breaking "Keep me logged in" only in release
# APKs, while `flutter run`'s debug builds (which never minify) worked
# fine the whole time. Deliberately broad (keep the whole package, not a
# narrow allowlist) because Firebase/GMS internals are tightly
# interconnected and a narrower rule set tends to miss edge cases, leading
# to exactly this kind of silent, hard-to-diagnose failure instead of a
# build error.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

-keep class com.google.android.libraries.** { *; }
-dontwarn com.google.android.libraries.**

# Parcelable CREATOR fields - Google Sign-In's account/credential objects
# are passed around as Parcelables, and losing the CREATOR field breaks
# reconstructing them after a process restart.
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}
-keep class * extends com.google.android.gms.common.internal.safeparcel.AbstractSafeParcelable {
    public static final *** CREATOR;
}
