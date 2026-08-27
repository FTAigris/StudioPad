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
    "StudioPad/Security/KeychainStore.swift",
    "StudioPad/Streaming/CameraStudioModel.swift",
    "StudioPad/Streaming/BroadcastConfigurationRelay.swift",
    "StudioPad/Views/CameraStudioView.swift",
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

if "exactVersion: 2.2.0" not in project_spec:
    fail("HaishinKit debe estar fijado exactamente a la versión revisada")

swift_text = "\n".join(
    file.read_text(encoding="utf-8") for file in ROOT.rglob("*.swift")
)
if swift_text.count("{") != swift_text.count("}"):
    fail("Las llaves del código Swift no están equilibradas")

for forbidden in ("a.rtmp.youtube.com/live2/", "live.twitch.tv/app/", "global-contribute.live-video.net"):
    if forbidden in swift_text:
        fail("Parece que se incluyó una clave o un destino privado en el código")

print("Proyecto verificado: estructura, plists y controles de secretos correctos.")
