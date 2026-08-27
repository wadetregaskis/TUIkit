#!/usr/bin/env python3
"""Is a running TUIkit app's right border a straight vertical line?

The end-to-end question — "did any row shear?" — asked of pixels rather than of
a person. A sheared row ends short or long, so the rightmost inked column
differs from its neighbours'. Nothing here recognises a glyph or reads a layout;
it finds the last column carrying ink on each scanline and asks whether they
agree.

This is the check that per-cluster measurement cannot replace. `landing_probe.py`
says what a terminal does to one cluster in isolation; this says whether the
whole pipeline — layout, claim, compensation, diff writer — put the right edge
where it belongs on a real screen full of real content.

    python3 border_probe.py SHOT.png [-o OUT.json]

Point it at a screenshot of the whole screen: it finds the app's own background
(TUIkit paints one, unlike a bare shell) and crops to that before measuring, so
the desktop and other windows cannot contribute an edge.

Exit status is 1 if any scanline's right edge is more than `--slack` pixels from
the modal one, so it can gate a smoke run.
"""
import argparse
import json
import sys
from collections import Counter

from PIL import Image

# How far a pixel must be from the background to count as ink, summed over RGB.
INK_DISTANCE = 60


def app_area(image):
    """Crop to the app's painted background, or return the image unchanged.

    A TUIkit app fills its screen with a background colour; a desktop does not.
    Taking the largest dark, high-count colour as that background finds the text
    area without needing the window's geometry from the window server — which is
    just as well, since asking for it needs an accessibility permission that
    hangs when it is not granted.
    """
    width, height = image.size
    counts = Counter(image.getdata())
    background = next(
        (colour for colour, n in counts.most_common(6)
         if sum(colour) < 90 and n > (width * height) // 12),
        None)
    if background is None:
        return image
    pixels = image.load()
    columns = [x for x in range(0, width, 4)
               if sum(1 for y in range(0, height, 4)
                      if pixels[x, y] == background) > 20]
    rows = [y for y in range(0, height, 4)
            if sum(1 for x in range(0, width, 4)
                   if pixels[x, y] == background) > 20]
    if not columns or not rows:
        return image
    return image.crop((min(columns), min(rows), max(columns) + 4, max(rows) + 4))


def right_edges(image):
    """The rightmost inked column of every scanline that carries ink."""
    width, height = image.size
    pixels = image.load()
    background = Counter(image.getdata()).most_common(1)[0][0]

    def inked(pixel):
        return sum(abs(a - b) for a, b in zip(pixel, background)) > INK_DISTANCE

    edges = []
    for y in range(height):
        for x in range(width - 1, -1, -1):
            if inked(pixels[x, y]):
                edges.append(x)
                break
    return edges


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("screenshot")
    parser.add_argument("-o", "--output")
    parser.add_argument("--slack", type=int, default=6,
                        help="pixels of tolerance around the modal right edge")
    arguments = parser.parse_args()

    image = app_area(Image.open(arguments.screenshot).convert("RGB"))
    edges = right_edges(image)
    if not edges:
        print("no ink found — wrong window, or the app never drew")
        return 2

    histogram = Counter(edges)
    modal, count = histogram.most_common(1)[0]
    outliers = sorted({edge for edge in edges if abs(edge - modal) > arguments.slack})

    result = {
        "scanlines_with_ink": len(edges),
        "modal_right_edge": modal,
        "fraction_at_modal": round(count / len(edges), 4),
        "outlier_edges": outliers,
    }
    if arguments.output:
        with open(arguments.output, "w") as handle:
            json.dump(result, handle, indent=1)

    print(f"{len(edges)} inked scanlines; right edge at {modal}px on "
          f"{count / len(edges):.1%} of them")
    if outliers:
        print(f"SHEARED: {len(outliers)} distinct right edges more than "
              f"{arguments.slack}px away: {outliers[:20]}")
        return 1
    print("no shear: every row ends in the same column")
    return 0


if __name__ == "__main__":
    sys.exit(main())
