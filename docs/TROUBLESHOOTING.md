# Troubleshooting Guide: Danoggin App (Flutter Project)

This document outlines known issues, configuration expectations, and recommended steps to resolve common problems encountered while building the **Danoggin** app in Flutter, particularly for Android.

---

## ✅ Working Configuration (as of April 2025)

| Component                    | Version / Setting                             |
|-----------------------------|-----------------------------------------------|
| Flutter SDK                 | 3.29.2 (stable)                                |
| Dart SDK                    | 3.7.2                                          |
| Java SDK                    | 17 (Eclipse Adoptium)                          |
| Gradle                      | 8.4                                            |
| Android Gradle Plugin (AGP) | 8.1.1                                          |
| Kotlin                      | 1.9.10                                         |
| compileSdkVersion           | 34                                             |
| targetSdkVersion            | 34                                             |
| minSdkVersion               | 21                                             |
| sourceCompatibility         | JavaVersion.VERSION_1_8                        |
| targetCompatibility         | JavaVersion.VERSION_1_8                        |

---

## ⚠️ Common Build Problems and Fixes

### 1. **Kotlin or AndroidX Errors**
```
Unresolved reference: FlutterActivity
Cannot access ComponentActivityViewModelLazy
```
**Fix:** Ensure `compileSdkVersion`, `targetSdkVersion`, and Kotlin version are correctly set (see config above).

---

### 2. **Gradle 7.6 or Version Mismatch Errors**
```
Minimum supported Gradle version is 8.0. Current version is 7.6
```
**Fix:** Update `android/gradle/wrapper/gradle-wrapper.properties`:
```
distributionUrl=https\://services.gradle.org/distributions/gradle-8.4-all.zip
```

---

### 3. **Java Version Problems**
```
Failed to load JDK image
or
Source/target value 17 is not supported
```
**Fix:**
- Make sure Java 17 is installed (Eclipse Adoptium JDK 17 recommended)
- Set `JAVA_HOME` to the Java 17 path
- Keep `sourceCompatibility` / `targetCompatibility` as `VERSION_1_8` for best Flutter plugin compatibility

---

### 4. **Daemon or Cache Corruption**
```
Cannot delete build folder
Old Gradle daemon keeps starting with Java 21
```
**Fix:**
- Kill all `java.exe`, `dart.exe`, `gradle` processes via Task Manager
- Delete:
  - `.gradle/` folders in project root and `android/`
  - `build/` folders in root and `android/`
  - Flutter cache: `flutter clean`

---

### 5. **`MainActivity.kt` Errors**
```
Unresolved reference: flutter_embedding_android
```
**Fix:**
Ensure `MainActivity.kt` looks like this:
```kotlin
package com.blue_vistas.danoggin

import io.flutter.embedding.android.FlutterActivity

class MainActivity: FlutterActivity() {}
```

---

## 🛠 Commands You’ll Use Often
```bash
flutter clean
flutter pub get
flutter build apk --verbose
flutter run
```

---

## 🧼 Recommended Cleanup (Full Reset)
1. Close VS Code and all related processes
2. Delete:
   - `.gradle/`
   - `.dart_tool/`
   - `build/`
3. Remove older Gradle caches in `C:\Users\<user>\.gradle\wrapper\dists`
4. Reboot if Java version still seems incorrect

---

## 📌 Tips
- Never mix direct Gradle CLI calls (`gradle build`) with Flutter's wrapper (`flutter build`) — always let Flutter drive the toolchain
- Java 17 may be your system default, but Gradle plugins usually expect your `build.gradle` settings to declare compatibility explicitly

---

## 🧭 When In Doubt
If all else fails, re-run the following:
```bash
flutter doctor -v
flutter clean && flutter pub get
flutter build apk --verbose
```
And inspect logs near the **first error line** for root causes.

---

_Last updated: April 3, 2025_

