#!/usr/bin/env python3
"""Adjusts the Android project that `flutter create` generates in CI.

The android/ folder is regenerated on each build, so the settings the app
needs are applied here instead of being hand-edited:

* minSdk at least 23 (required by Firebase Authentication)
* app name shown on the phone: "Chat Aduunka"
* INTERNET, POST_NOTIFICATIONS and CAMERA permissions

The script is idempotent and works with both Groovy and Kotlin Gradle files.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
APP = ROOT / "android" / "app"
MIN_SDK = 23


def patch_gradle() -> None:
    for name in ("build.gradle.kts", "build.gradle"):
        path = APP / name
        if not path.exists():
            continue
        text = path.read_text()
        original = text
        # Kotlin DSL: minSdk = flutter.minSdkVersion  /  minSdk = 21
        text = re.sub(
            r"minSdk\s*=\s*(flutter\.minSdkVersion|\d+)",
            f"minSdk = maxOf(flutter.minSdkVersion, {MIN_SDK})" if name.endswith(".kts")
            else f"minSdk = Math.max(flutter.minSdkVersion, {MIN_SDK})",
            text,
        )
        # Groovy DSL: minSdkVersion flutter.minSdkVersion
        text = re.sub(
            r"minSdkVersion\s+(flutter\.minSdkVersion|\d+)",
            f"minSdkVersion Math.max(flutter.minSdkVersion, {MIN_SDK})",
            text,
        )
        if text != original:
            path.write_text(text)
        print(f"{path}: minSdk >= {MIN_SDK}")
        print("\n".join(l for l in text.splitlines() if "minSdk" in l or "applicationId" in l))
        return
    sys.exit("No app Gradle file found")


def patch_manifest() -> None:
    path = APP / "src" / "main" / "AndroidManifest.xml"
    text = path.read_text()
    text = re.sub(r'android:label="[^"]*"', 'android:label="Chat Aduunka"', text, count=1)
    for perm in ("INTERNET", "POST_NOTIFICATIONS", "CAMERA"):
        line = f'<uses-permission android:name="android.permission.{perm}"/>'
        if f"android.permission.{perm}\"" not in text:
            text = re.sub(r"(<manifest[^>]*>)", r"\1\n    " + line, text, count=1)
    # Camera is optional so phones without one can still install the app.
    feature = '<uses-feature android:name="android.hardware.camera" android:required="false"/>'
    if "android.hardware.camera" not in text:
        text = re.sub(r"(<manifest[^>]*>)", r"\1\n    " + feature, text, count=1)
    path.write_text(text)
    print(f"{path}: label and permissions set")


if __name__ == "__main__":
    patch_gradle()
    patch_manifest()
