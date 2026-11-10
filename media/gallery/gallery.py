"""Builds the gallery images (1920x1080 JPG) from the cut-out reference screenshots (src/crop/*.png,
see crop.py): each window centred on the backdrop colour it was photographed in front of, scaled down
only where it is wider than the picture.

    python media/gallery/gallery.py

The pictures keep the file names the README and the CurseForge description already link to.
"""
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CROP = os.path.join(HERE, "src", "crop")
W, H = 1920, 1080
MARGIN = 40

# gallery picture <- reference screenshot (UI/Shots.lua)
PICTURES = [
    ("01-chat", "01-chat"),
    ("02-members", "02-members"),
    ("03-overview", "03-overview"),
    ("04-hall-of-fame", "04-fame-general"),
    ("05-hall-of-fame-economy", "05-fame-economy"),
    ("06-hall-of-fame-dungeons", "06-fame-dungeons"),
    ("07-hall-of-fame-reputation", "07-fame-reputation"),
    ("08-hall-of-fame-pvp", "08-fame-pvp"),
    ("09-professions", "09-professions"),
    ("10-info-log", "10-info"),
    ("11-ranks", "11-ranks"),
    ("13-account", "12-account"),
    ("14-character", "14-character"),
    ("15-options-members", "17-options-members"),
    ("16-options-hall-of-fame", "18-options-fame"),
]


def main():
    for target, source in PICTURES:
        img = Image.open(os.path.join(CROP, source + ".png")).convert("RGB")
        scale = min(1.0, (W - 2 * MARGIN) / img.width, (H - 2 * MARGIN) / img.height)
        if scale < 1.0:
            img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
        canvas = Image.new("RGB", (W, H), img.getpixel((2, img.height - 3)))
        canvas.paste(img, ((W - img.width) // 2, (H - img.height) // 2))
        canvas.save(os.path.join(HERE, target + ".jpg"), quality=92)
        print("%s.jpg  <-  %s.png  (%d%%)" % (target, source, round(scale * 100)))


if __name__ == "__main__":
    main()
