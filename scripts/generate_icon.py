from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


SIZE = 1024
OUTPUT = (
    Path(__file__).resolve().parents[1]
    / "StudioPad"
    / "Assets.xcassets"
    / "AppIcon.appiconset"
    / "StudioPadIcon.png"
)

image = Image.new("RGB", (SIZE, SIZE))
pixels = image.load()
for y in range(SIZE):
    ratio = y / (SIZE - 1)
    color = (
        int(11 + (35 - 11) * ratio),
        int(14 + (13 - 14) * ratio),
        int(24 + (24 - 24) * ratio),
    )
    for x in range(SIZE):
        pixels[x, y] = color

draw = ImageDraw.Draw(image)
red = (244, 45, 64)
white = (249, 250, 252)

draw.rounded_rectangle((205, 205, 819, 819), radius=155, fill=(25, 27, 38))
draw.arc((130, 280, 650, 744), start=112, end=248, fill=red, width=42)
draw.arc((374, 280, 894, 744), start=-68, end=68, fill=red, width=42)
draw.ellipse((437, 437, 587, 587), fill=red)

try:
    font = ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", 230)
except OSError:
    font = ImageFont.load_default()

text = "SP"
box = draw.textbbox((0, 0), text, font=font)
text_width = box[2] - box[0]
draw.text(((SIZE - text_width) / 2, 530), text, font=font, fill=white, anchor="ma")

OUTPUT.parent.mkdir(parents=True, exist_ok=True)
image.save(OUTPUT, format="PNG", optimize=True)
print(OUTPUT)
