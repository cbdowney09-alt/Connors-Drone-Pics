from PIL import Image, ImageDraw, ImageFont
import os

ACCENT = (79, 110, 247)  # #4f6ef7, matches --accent in styles.css
WHITE = (255, 255, 255)
FONT_PATH = r"C:\Windows\Fonts\arialbd.ttf"
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "public")


def make_icon(size, filename):
    img = Image.new("RGB", (size, size), ACCENT)
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype(FONT_PATH, int(size * 0.62))
    text = "K"
    bbox = draw.textbbox((0, 0), text, font=font)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x = (size - w) / 2 - bbox[0]
    y = (size - h) / 2 - bbox[1]
    draw.text((x, y), text, font=font, fill=WHITE)
    img.save(os.path.join(OUT_DIR, filename))
    print(f"wrote {filename} ({size}x{size})")


os.makedirs(OUT_DIR, exist_ok=True)
make_icon(192, "icon-192.png")
make_icon(512, "icon-512.png")
make_icon(180, "apple-touch-icon.png")
make_icon(32, "favicon.png")
