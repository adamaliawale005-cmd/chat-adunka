#!/usr/bin/env python3
"""Adds AduChat's permission texts and settings to the generated iOS and
macOS projects (run after `flutter create`). Safe to run more than once."""
import pathlib, re, sys

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")

usage = {
    "NSCameraUsageDescription": "AduChat uses the camera for video calls and to take photos you send.",
    "NSMicrophoneUsageDescription": "AduChat uses the microphone for calls and voice messages.",
    "NSPhotoLibraryUsageDescription": "AduChat lets you choose photos and videos to send.",
    "NSPhotoLibraryAddUsageDescription": "AduChat can save photos you receive.",
    "NSContactsUsageDescription": "If you allow it, AduChat finds which of your contacts use AduChat.",
}


def add_keys(plist: pathlib.Path, extra: dict):
    if not plist.exists():
        return
    s = plist.read_text()
    add = ""
    for k, v in {**usage, **extra}.items():
        if f"<key>{k}</key>" in s:
            continue
        if isinstance(v, bool):
            add += f"\t<key>{k}</key>\n\t<{'true' if v else 'false'}/>\n"
        elif isinstance(v, list):
            add += f"\t<key>{k}</key>\n\t<array>\n" + "".join(f"\t\t<string>{x}</string>\n" for x in v) + "\t</array>\n"
        else:
            add += f"\t<key>{k}</key>\n\t<string>{v}</string>\n"
    s = s.replace("<key>CFBundleDisplayName</key>\n\t<string>Chat Adunka</string>",
                  "<key>CFBundleDisplayName</key>\n\t<string>AduChat</string>")
    s = re.sub(r"</dict>\s*</plist>\s*$", add + "</dict>\n</plist>\n", s)
    plist.write_text(s)
    print("updated", plist)


add_keys(root / "ios/Runner/Info.plist", {
    "UIBackgroundModes": ["audio", "voip", "remote-notification", "fetch"],
    "ITSAppUsesNonExemptEncryption": False,
})
add_keys(root / "macos/Runner/Info.plist", {})

# Firebase and WebRTC need iOS 13 / macOS 10.15 or later.
pod = root / "ios/Podfile"
if pod.exists():
    s = pod.read_text()
    s = re.sub(r"^#?\s*platform :ios, '[\d.]+'", "platform :ios, '13.0'", s, flags=re.M)
    pod.write_text(s)
mpod = root / "macos/Podfile"
if mpod.exists():
    s = mpod.read_text()
    s = re.sub(r"^#?\s*platform :osx, '[\d.]+'", "platform :osx, '10.15'", s, flags=re.M)
    mpod.write_text(s)

# macOS sandbox: network, camera, microphone, user-selected files.
for ent in ("DebugProfile.entitlements", "Release.entitlements"):
    f = root / "macos/Runner" / ent
    if not f.exists():
        continue
    s = f.read_text()
    for k in ("com.apple.security.network.client", "com.apple.security.device.camera",
              "com.apple.security.device.audio-input", "com.apple.security.files.user-selected.read-write"):
        if k not in s:
            s = s.replace("</dict>", f"\t<key>{k}</key>\n\t<true/>\n</dict>", 1)
    f.write_text(s)
    print("updated", f)
