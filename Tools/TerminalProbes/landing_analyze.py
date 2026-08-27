#!/usr/bin/env python3
"""Read `landing_probe.py`'s screenshots and say which column each marker is in.

The reading is arithmetic on pixels, not a judgement about a picture. Three
green calibration marks at known cells pin the pixel grid; each cluster's
magenta marker is then found by colour, width **and full cell height**, and its
column falls out of the grid. Nothing here recognises a glyph or decides whether
something looks right.

    python3 landing_analyze.py MANIFEST.json -o data/<host>.json

The full-height requirement is not fussiness. A first version took the first
magenta run on the row's middle scanline and duly reported that 🏳️‍🌈 lands
seven cells along, because the flag has a magenta stripe and a stripe is a wide
run of the right colour. A marker is a *background*: solid from the top of the
cell to the bottom. Emoji ink is not.

The output is a measurement record: per cluster, the DSR `advance` the probe
read, the `landing` measured here, and `reserve` if the probe was run with
`--wrap`. Compare it against TUIkit's models with

    swift test --filter TerminalLedgerConformanceTests
"""
import argparse
import json
import sys

from PIL import Image

# Marker and calibration colours as the 6x6x6 cube renders them: index 201 is
# (5,0,5) and index 46 is (0,5,0). The tolerance covers a terminal that dims or
# gamma-corrects its palette slightly; it is nowhere near wide enough to admit
# the other colour.
MARKER_RGB = (255, 0, 255)
CALIB_RGB = (0, 255, 0)
TOLERANCE = 60

# A mark is two cells of solid colour. Nothing else in a screenshot is: stray
# green in a wallpaper or antialiased text gives runs of a pixel or three, and
# an early version of this took the topmost of those for a mark and calibrated
# the grid off a highlight two hundred pixels above the terminal.
MIN_MARK_PIXELS = 8
# How much of a cell's height the colour must cover to count as a background
# rather than ink, and how much of its width to count as a marker.
SOLID_FRACTION = 0.85
MIN_MARKER_CELLS = 1.2


def mask_for(image, target):
    """A 0/255 `L` image, 255 where the pixel is within tolerance of `target`."""
    red, green, blue = image.split()[:3]

    def near(band, value):
        return band.point([255 if abs(i - value) <= TOLERANCE else 0 for i in range(256)])

    result = near(red, target[0])
    for band, value in ((green, target[1]), (blue, target[2])):
        result = Image.composite(near(band, value), Image.new("L", image.size, 0), result)
    return result


class Scan:
    """Row-wise access to a mask, by raw bytes — fast enough without numpy."""

    def __init__(self, mask):
        self.mask = mask
        self.width, self.height = mask.size
        self.data = mask.tobytes()

    def row(self, y):
        return self.data[y * self.width:(y + 1) * self.width]

    def runs(self, y, minimum=1):
        """Start and end of each horizontal run of set pixels at least `minimum` long."""
        row, found, index = self.row(y), [], 0
        while True:
            start = row.find(255, index)
            if start < 0:
                return found
            end = start
            while end < len(row) and row[end] == 255:
                end += 1
            if end - start >= minimum:
                found.append((start, end))
            index = end

    def solid_runs(self, top, bottom, minimum):
        """Runs of columns set on (nearly) every scanline between `top` and `bottom`.

        Averaged in C by resizing the band to a single row, so the whole band is
        one pass rather than a Python loop per pixel.
        """
        top, bottom = max(0, int(top)), min(self.height, int(bottom))
        if bottom - top < 2:
            return []
        band = self.mask.crop((0, top, self.width, bottom))
        profile = band.resize((self.width, 1), Image.BOX).tobytes()
        threshold = int(255 * SOLID_FRACTION)
        found, index = [], 0
        while index < self.width:
            if profile[index] < threshold:
                index += 1
                continue
            start = index
            while index < self.width and profile[index] >= threshold:
                index += 1
            if index - start >= minimum:
                found.append((start, index))
        return found


def calibrate(green, magenta, last_row, calibration_cells):
    """Pixel origin and cell size, from the three calibration marks.

    A mark is a green rectangle with a magenta one welded to its right edge.
    Green alone is not enough: a whole-screen capture holds a wallpaper, other
    applications and this terminal's own windows from earlier runs, and any of
    them can contain a green rectangle. An earlier version calibrated off a
    stale window three runs old, and every number it then produced was wrong in
    a way that looked entirely plausible.
    """
    def marks_on(y):
        greens = green.runs(y, minimum=MIN_MARK_PIXELS)
        magentas = magenta.runs(y, minimum=MIN_MARK_PIXELS)
        starts = {start for start, _ in magentas}
        return [(start, end) for start, end in greens
                if any(abs(end - other) <= 2 for other in starts)]

    rows = [y for y in range(green.height) if marks_on(y)]
    if not rows:
        raise SystemExit("no calibration marks found — wrong window, or a "
                         "translucent one, or a palette that does not match")

    top = rows[0]
    height = 1
    while top + height < green.height and marks_on(top + height):
        height += 1
    marks = marks_on(top + height // 2)
    if len(marks) != 2:
        raise SystemExit(f"expected 2 calibration marks on the top row, found {len(marks)}")

    bottom = rows[-1]
    while bottom - 1 > top + height and marks_on(bottom - 1):
        bottom -= 1

    cell_width = (marks[1][0] - marks[0][0]) / 70  # columns 1 and 71
    cell_height = (bottom - top) / (last_row - 1)  # rows 1 and last_row
    if cell_width <= 0 or cell_height <= 0:
        raise SystemExit("calibration marks are in the wrong order")
    return {
        "origin_x": marks[0][0], "origin_y": top,
        "cell_width": cell_width, "cell_height": cell_height,
    }


def ink_cells(image, grid, row, from_column, until_column):
    """How many cells of the glyph at `from_column` actually carry ink.

    An independent cross-check on `landing`, and the number that says whether a
    gap is the terminal drawing narrow or the terminal mispositioning what
    follows. The background is taken as the most common colour in the row's own
    band, so it needs no knowledge of the terminal's theme; a cell counts as
    inked if enough of it differs from that.
    """
    top = int(grid["origin_y"] + (row - 1) * grid["cell_height"])
    bottom = int(top + grid["cell_height"])
    left = int(grid["origin_x"] + (from_column - 1) * grid["cell_width"])
    right = int(grid["origin_x"] + (until_column - 1) * grid["cell_width"])
    if right <= left or bottom <= top:
        return None
    band = image.crop((left, top, right, bottom))
    colours = band.getcolors(band.size[0] * band.size[1]) or []
    if not colours:
        return None
    background = max(colours)[1]

    def differs(pixel):
        return sum(abs(a - b) for a, b in zip(pixel, background)) > 90

    cells = 0
    for index in range(until_column - from_column):
        cell = band.crop((int(index * grid["cell_width"]), 0,
                          int((index + 1) * grid["cell_width"]), band.size[1]))
        pixels = list(cell.getdata())
        if pixels and sum(1 for p in pixels if differs(p)) > len(pixels) * 0.02:
            cells = index + 1
    return cells


def marker_column(scan, grid, row, from_column, marker_cells):
    """The 1-based column the first marker at or after `from_column` starts in.

    Measured from the marker's RIGHT edge and counted back by its known width.
    Its left edge is not usable: a wide glyph's ink reaches into the cell the
    marker begins in, which drops that cell below the solid-colour threshold
    and reads as a marker one cell further along. An early version measured
    left edges and reported that every Apple Terminal skin-tone cluster lands
    one cell further right than it does.
    """
    top = grid["origin_y"] + (row - 1) * grid["cell_height"]
    inset = grid["cell_height"] * 0.1
    runs = scan.solid_runs(top + inset, top + grid["cell_height"] - inset,
                           minimum=max(2, int(grid["cell_width"] * MIN_MARKER_CELLS)))
    # A quarter-cell of slack for a glyph that overhangs its cell to the left.
    start = (grid["origin_x"] + (from_column - 1) * grid["cell_width"]
             - grid["cell_width"] / 4)
    for run_start, run_end in runs:
        if run_end <= start:
            continue
        after = round((run_end - grid["origin_x"]) / grid["cell_width"])
        return after - marker_cells + 1
    return None


# Clusters whose landing is known before any terminal is asked: one cell for a
# plain ASCII character, two for an East-Asian-Wide one. No terminal disagrees
# about these, so if the instrument does, the instrument is off — and it was, by
# exactly one cell on iTerm2, uniformly, including for `a`. Reading that as a
# terminal behaviour would have "corrected" all sixty-nine clusters on a host
# that gets every one of them right.
CONTROLS = {
    "ascii_a": 1, "ascii_bracket": 1, "halfwidth_kana": 1,
    "cjk_han": 2, "hangul": 2,
}


def instrument_bias(measurements):
    """How far the instrument reads high on this host, from the controls alone."""
    seen = {}
    for name, expected in CONTROLS.items():
        if name in measurements:
            seen[name] = measurements[name] - expected
    if not seen:
        raise SystemExit("no control clusters measured — cannot trust the readings")
    biases = set(seen.values())
    if len(biases) > 1:
        detail = ", ".join(f"{name} {bias:+d}" for name, bias in sorted(seen.items()))
        raise SystemExit(
            f"the controls disagree about the instrument's offset ({detail}); "
            "the grid is wrong in a way a single correction cannot fix")
    return biases.pop()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest")
    parser.add_argument("-o", "--output", required=True)
    arguments = parser.parse_args()

    with open(arguments.manifest) as handle:
        manifest = json.load(handle)

    layout = manifest["grid"]
    marker_cells = layout["marker_cells"]
    pages = {page["index"]: page for page in manifest["pages"]}
    grids, markers, images = {}, {}, {}
    for index, page in pages.items():
        if not page.get("screenshot"):
            raise SystemExit(f"page {index} has no screenshot — rerun the probe "
                             "with PROBE_SHOT set")
        image = Image.open(page["screenshot"]).convert("RGB")
        images[index] = image
        markers[index] = Scan(mask_for(image, MARKER_RGB))
        grids[index] = calibrate(Scan(mask_for(image, CALIB_RGB)), markers[index],
                                 page["last_row"], layout["calibration_cells"])
        # The page's own self-check: a marker at a column the probe chose, with
        # nothing in front of it. Read it back before reading anything else.
        read = marker_column(markers[index], grids[index], layout["self_check_row"],
                             1, marker_cells)
        if read != layout["self_check_column"]:
            raise SystemExit(
                f"page {index} self-check failed: a marker placed at column "
                f"{layout['self_check_column']} reads as {read}. The grid is "
                f"wrong, so every measurement on this page would be too.")

    raw, missing = {}, []
    for cell in manifest["cells"]:
        page = cell.get("page", 0)
        column = marker_column(markers[page], grids[page], cell["row"],
                               cell["column"], marker_cells)
        if column is None:
            missing.append(cell["id"])
            continue
        record = {
            "class": cell["class"],
            "advance": cell["advance"],
            "landing": column - cell["column"],
            "ink": ink_cells(images[page], grids[page], cell["ink_row"],
                             cell["column"],
                             cell["column"] + layout["ink_cells"]),
        }
        if cell.get("reserve") is not None:
            record["reserve"] = cell["reserve"]
        raw[cell["id"]] = record

    bias = instrument_bias({name: record["landing"] for name, record in raw.items()})
    measurements = {}
    for name, record in raw.items():
        corrected = dict(record)
        corrected["landing"] = record["landing"] - bias
        if corrected["ink"] is not None:
            corrected["ink"] = max(0, record["ink"] - bias)
        measurements[name] = corrected

    document = {
        "stamp": manifest.get("stamp", {}),
        "instrument_bias": bias,
        "grid": {index: {key: round(value, 3) for key, value in grid.items()}
                 for index, grid in grids.items()},
        "measurements": measurements,
    }
    with open(arguments.output, "w") as handle:
        json.dump(document, handle, indent=1, sort_keys=True)

    print(f"{len(measurements)} measured -> {arguments.output}"
          + (f" (instrument read {bias:+d} on the controls; corrected)" if bias else ""))
    for index, grid in sorted(grids.items()):
        print(f"page {index}: cell {grid['cell_width']:.2f}x{grid['cell_height']:.2f}px "
              f"at ({grid['origin_x']}, {grid['origin_y']})")
    if missing:
        print(f"NO MARKER FOUND for {len(missing)}: {', '.join(missing)}")
    def report(title, predicate):
        rows = [(name, record) for name, record in sorted(measurements.items())
                if predicate(record)]
        if not rows:
            return
        print(f"\n{title} ({len(rows)}):")
        for name, record in rows:
            print(f"  {name}: advance {record['advance']}, lands at "
                  f"{record['landing']}, inks {record['ink']}"
                  + (f", reserves {record['reserve']}" if "reserve" in record else ""))

    # The three things that can be wrong, kept apart because the fixes differ.
    report("The next character OVERLAPS the glyph (under-spaced)",
           lambda r: r["ink"] is not None and r["ink"] > r["landing"])
    report("The next character leaves a GAP (over-spaced)",
           lambda r: r["ink"] is not None and r["ink"] < r["landing"])
    report("DSR disagrees with paint",
           lambda r: r["advance"] != r["landing"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
