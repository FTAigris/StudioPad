from __future__ import annotations

import plistlib
import json
import re
import struct
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

EXPECTED_FILES = [
    "project.yml",
    "StudioPad/Info.plist",
    "StudioPad/Assets.xcassets/AppIcon.appiconset/Contents.json",
    "StudioPad/Assets.xcassets/AppIcon.appiconset/StudioPadIcon.png",
    "StudioPad/StudioPadApp.swift",
    "StudioPad/Models/StreamConfiguration.swift",
    "StudioPad/Models/StudioModels.swift",
    "StudioPad/Security/KeychainStore.swift",
    "StudioPad/Streaming/CameraStudioModel.swift",
    "StudioPad/Streaming/ExternalDisplayManager.swift",
    "StudioPad/Streaming/BroadcastConfigurationRelay.swift",
    "StudioPad/Views/CameraStudioView.swift",
    "StudioPad/Views/StudioConsoleView.swift",
    "StudioPad/Views/ScreenStudioView.swift",
    "ScreenBroadcast/Info.plist",
    "ScreenBroadcast/SampleHandler.swift",
    "ScreenBroadcast/BroadcastConfigurationReceiver.swift",
    "BroadcastSetup/Info.plist",
    "BroadcastSetup/SetupViewController.swift",
    "Shared/BroadcastConstants.swift",
    ".github/workflows/build-unsigned-ipa.yml",
]


def fail(message: str) -> None:
    print(f"ERROR: {message}")
    raise SystemExit(1)


for relative_path in EXPECTED_FILES:
    if not (ROOT / relative_path).is_file():
        fail(f"Falta {relative_path}")

for plist_path in ROOT.rglob("Info.plist"):
    try:
        with plist_path.open("rb") as file:
            plistlib.load(file)
    except Exception as error:  # pragma: no cover - utility script
        fail(f"{plist_path.relative_to(ROOT)} no es válido: {error}")

with (ROOT / "StudioPad/Info.plist").open("rb") as file:
    app_info = plistlib.load(file)
for usage_key in ("NSCameraUsageDescription", "NSMicrophoneUsageDescription"):
    if not app_info.get(usage_key):
        fail(f"StudioPad/Info.plist no contiene {usage_key}")

with (ROOT / "ScreenBroadcast/Info.plist").open("rb") as file:
    upload_info = plistlib.load(file)
upload_extension = upload_info.get("NSExtension", {})
if upload_extension.get("NSExtensionPointIdentifier") != "com.apple.broadcast-services-upload":
    fail("ScreenBroadcast no declara el punto de extensión de ReplayKit")
if upload_extension.get("NSExtensionAttributes", {}).get("RPBroadcastProcessMode") != "RPBroadcastProcessModeSampleBuffer":
    fail("ScreenBroadcast no declara el modo SampleBuffer de ReplayKit")

with (ROOT / "BroadcastSetup/Info.plist").open("rb") as file:
    setup_info = plistlib.load(file)
if setup_info.get("NSExtension", {}).get("NSExtensionPointIdentifier") != "com.apple.broadcast-services-setupui":
    fail("BroadcastSetup no declara el punto de extensión de ReplayKit")

for json_path in ROOT.rglob("*.json"):
    try:
        json.loads(json_path.read_text(encoding="utf-8"))
    except Exception as error:  # pragma: no cover - utility script
        fail(f"{json_path.relative_to(ROOT)} no es válido: {error}")

icon_header = (
    ROOT / "StudioPad/Assets.xcassets/AppIcon.appiconset/StudioPadIcon.png"
).read_bytes()[:24]
if icon_header[:8] != b"\x89PNG\r\n\x1a\n":
    fail("El icono no es un PNG válido")
width, height = struct.unpack(">II", icon_header[16:24])
if (width, height) != (1024, 1024):
    fail("El icono debe medir 1024 por 1024 píxeles")

project_spec = (ROOT / "project.yml").read_text(encoding="utf-8")
for target in ("StudioPad", "ScreenBroadcast", "BroadcastSetup"):
    if not re.search(rf"^  {re.escape(target)}:\s*$", project_spec, re.MULTILINE):
        fail(f"El destino {target} no aparece en project.yml")

for plist_path in ("StudioPad/Info.plist", "ScreenBroadcast/Info.plist", "BroadcastSetup/Info.plist"):
    if f"INFOPLIST_FILE: {plist_path}" not in project_spec:
        fail(f"project.yml no conserva {plist_path}")

if re.search(r"^\s+info:\s*$", project_spec, re.MULTILINE):
    fail("project.yml no debe pedir a XcodeGen que regenere los Info.plist")

if "exactVersion: 2.2.5" not in project_spec:
    fail("HaishinKit debe estar fijado exactamente a la versión revisada")

swift_text = "\n".join(
    file.read_text(encoding="utf-8") for file in ROOT.rglob("*.swift")
)
if swift_text.count("{") != swift_text.count("}"):
    fail("Las llaves del código Swift no están equilibradas")

for unsupported_symbol in ("StreamSession", "StreamSessionBuilderFactory"):
    if unsupported_symbol in swift_text:
        fail(f"{unsupported_symbol} no está disponible en HaishinKit 2.2.5")

for forbidden in ("a.rtmp.youtube.com/live2/", "live.twitch.tv/app/", "global-contribute.live-video.net"):
    if forbidden in swift_text:
        fail("Parece que se incluyó una clave o un destino privado en el código")

print("Proyecto verificado: estructura, plists y controles de secretos correctos.")
