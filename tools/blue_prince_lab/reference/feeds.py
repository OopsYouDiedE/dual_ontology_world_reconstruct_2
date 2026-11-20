"""Build the CRT atlas from eight locally captured game views, in reading order."""
import argparse
from PIL import Image, ImageOps
from mesh import OUT

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('frames', nargs=8, metavar='PNG')
    args = parser.parse_args()
    sheet = Image.new('RGB', (1280, 480))
    for i, path in enumerate(args.frames):
        with Image.open(path) as frame:
            crop = ImageOps.fit(frame.convert('RGB'), (320, 240), centering=((.25+i*.14)%1, .56))
        sheet.paste(ImageOps.autocontrast(crop, cutoff=1), (i%4*320, i//4*240))
    sheet.save(OUT/'interface/Feeds.jpg', quality=93)
