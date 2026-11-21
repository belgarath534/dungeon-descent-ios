"""Draws the Game Center challenge pictures (store/game-center/*.png):
the game's dark background, a gold border and the challenge's name in
Cinzel Decorative, like the loading screen. 3840 x 2160, the size Apple
requires for challenge pictures."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

FONTS = os.path.join(os.path.dirname(__file__), "../swift/App/DungeonDescent/Fonts")
OUT = os.path.join(os.path.dirname(__file__), "../store/game-center")
ART = {
    "DD_CHALLENGE_ENDLESS_BEST_FLOOR": ("Endless Descent", "How deep can you go?"),
    "DD_CHALLENGE_WEEKLY_LADDER": ("Weekly Ladder", "One dungeon. One life. One week."),
    "DD_CHALLENGE_SPIRE_BEST_FLOOR": ("The Spire", "Climb higher than your friends."),
}
K = 2  # drawn at 1920 x 1080, scaled up
W, H = 1920 * K, 1080 * K
GOLD, DIM = (224, 192, 128), (139, 115, 64)

for key, (title, line) in ART.items():
    img = Image.new("RGB", (W, H), (8, 6, 16))
    # A soft gold glow in the middle.
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    ImageDraw.Draw(glow).ellipse((W * 0.2, H * 0.15, W * 0.8, H * 0.85), fill=(70, 50, 20))
    img = Image.blend(img, glow.filter(ImageFilter.GaussianBlur(220 * K)), 0.6)
    d = ImageDraw.Draw(img)
    d.rectangle((60 * K, 60 * K, W - 60 * K, H - 60 * K), outline=DIM, width=4 * K)
    d.rectangle((80 * K, 80 * K, W - 80 * K, H - 80 * K), outline=(60, 48, 28), width=2 * K)
    small = ImageFont.truetype(f"{FONTS}/Cinzel-Variable.ttf", 46)
    big = ImageFont.truetype(f"{FONTS}/CinzelDecorative-Bold.ttf", 150 * K)
    sub = ImageFont.truetype(f"{FONTS}/Cinzel-Variable.ttf", 58)
    for text, font, y, color in (("DUNGEON DESCENT", small, 300 * K, DIM), (title, big, 470 * K, GOLD), (line, sub, 700 * K, (200, 190, 170))):
        w = d.textlength(text, font=font)
        d.text(((W - w) / 2, y), text, font=font, fill=color)
    img.save(f"{OUT}/{key}.png", optimize=True)
    print("drew", key)
