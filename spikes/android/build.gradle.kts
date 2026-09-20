// Root build file for the Android M0 spike harness (spikes/android).
// This is a Flutter-independent, minimal Gradle project. See README.md for
// how it relates to design.md §4.3 / §5 / §7 / §8 and tasks.md M0 Android.

plugins {
    id("com.android.application") version "9.4.1" apply false
    // AGP 9.0 以降は Kotlin サポートが組み込まれているため、org.jetbrains.kotlin.android
    // プラグインは適用しない (適用するとエラーになる。https://issuetracker.google.com/438678642)。
}
