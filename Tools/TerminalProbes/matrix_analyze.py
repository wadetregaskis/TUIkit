#!/usr/bin/env python3
"""Read `matrix_probe.py`'s screenshots: paint landing, ink, and APPEARANCE.

Appearance is the one question DSR cannot answer — whether a strategy's glyph
came out composed, stripped to its base, detached into base + swatch, or
something else — and it is answered mechanically, not by a person: the probe
rendered every reference glyph (the composed cluster, the stripped base, the
bare base, the lone modifier) in the same run, same font, same grid, and each
test cell is classified by nearest-reference pixel distance.

    python3 matrix_analyze.py MANIFEST.json -o data/<host>-matrix.json

The output merges the DSR phase (already in the manifest) with the pixel
readings into one truth table: per (cluster, strategy) —
advance / wrapped / landing / ink / appearance.
"""
import argparse
import json
import sys

from PIL import Image

from landing_analyze import (CALIB_RGB, MARKER_RGB, Scan, calibrate,
                             ink_cells, marker_column, mask_for)


def cell_image(image, grid, row, from_column, until_column):
    cw, ch = grid["cell_width"], grid["cell_height"]
    left = grid["origin_x"] + (from_column - 1) * cw
    top = grid["origin_y"] + (row - 1) * ch
    return image.crop((int(left), int(top),
                       int(grid["origin_x"] + (until_column - 1) * cw),
                       int(top + ch)))


def glyph_signature(image, grid, row, columns):
    """A small normalised thumbnail of the glyph's cells, for comparison."""
    region = cell_image(image, grid, row, 1, 1 + columns)
    return list(region.resize((16, 16), Image.BOX).getdata())


def distance(a, b):
    return sum(sum(abs(x - y) for x, y in zip(pa, pb)) for pa, pb in zip(a, b))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest")
    parser.add_argument("-o", "--output", required=True)
    arguments = parser.parse_args()

    with open(arguments.manifest) as handle:
        manifest = json.load(handle)
    pixels = manifest.get("pixels")
    if not pixels:
        raise SystemExit("this manifest has no pixel phase — rerun matrix_probe.py "
                         "with PROBE_SHOT set (and a display attached)")

    pages = {p["index"]: p for p in pixels["pages"]}
    images, grids, markers = {}, {}, {}
    for index, page in pages.items():
        image = Image.open(page["screenshot"]).convert("RGB")
        images[index] = image
        markers[index] = Scan(mask_for(image, MARKER_RGB))
        grids[index] = calibrate(Scan(mask_for(image, CALIB_RGB)), markers[index],
                                 page["last_row"], 2)

    # Reference signatures, keyed (kind, cluster id). Two widths per reference:
    # the glyph's own cells and one extra, so a composed-vs-stripped comparison
    # is not confused by antialiased spill.
    # Reference signatures AND their source cells, keyed (kind, GLYPH text):
    # the probe deduplicates reference rows per glyph, so an id-keyed lookup
    # missed every cluster whose part had already been drawn for an earlier
    # one — and the swatch crop must come from the reference cell's OWN page,
    # not the test cell's (an earlier version mixed the two, comparing the
    # swatch against whatever row sat at that number on the wrong page).
    references, reference_cells = {}, {}
    for cell in pixels["cells"]:
        if cell["kind"] == "test":
            continue
        page = cell["page"]
        key = (cell["kind"], cell["text"])
        references[key] = glyph_signature(images[page], grids[page], cell["row"], 4)
        reference_cells[key] = cell

    def classify(cell):
        page = cell["page"]
        signature = glyph_signature(images[page], grids[page], cell["ink_row"], 4)
        own = [("ref_raw", cell["text"]), ("ref_strip", cell.get("stripped")),
               ("ref_base", cell.get("base")), ("ref_mod", cell.get("modifier"))]
        candidates = []
        for kind, text in own:
            reference = references.get((kind, text)) if text else None
            if reference is not None:
                candidates.append((distance(signature, reference), kind))
        if not candidates:
            return None, None
        candidates.sort()
        best_distance, best_kind = candidates[0]
        label = {"ref_raw": "composed", "ref_strip": "stripped",
                 "ref_base": "base-only", "ref_mod": "modifier-only"}[best_kind]
        # Detached = the base in its cells AND the modifier's swatch beside it.
        # Compare cells 3..4 against the lone-modifier reference directly.
        base_reference = references.get(("ref_base", cell.get("base")))
        modifier_cell = reference_cells.get(("ref_mod", cell.get("modifier")))
        raw_reference = references.get(("ref_raw", cell["text"]))
        if base_reference is not None and modifier_cell is not None and raw_reference is not None:
            beside = cell_image(images[page], grids[page], cell["ink_row"],
                                cell["claim"] + 1, cell["claim"] + 5)
            beside_signature = list(beside.resize((16, 16), Image.BOX).getdata())
            swatch_page = modifier_cell["page"]
            swatch = cell_image(images[swatch_page], grids[swatch_page],
                                modifier_cell["row"], 1, 5)
            swatch_signature = list(swatch.resize((16, 16), Image.BOX).getdata())
            if (distance(signature, base_reference) < distance(signature, raw_reference)
                    and distance(beside_signature, swatch_signature) < 16 * 16 * 90):
                label = "detached"
        return label, best_distance

    results = []
    for cell in pixels["cells"]:
        if cell["kind"] != "test":
            continue
        page = cell["page"]
        column = marker_column(markers[page], grids[page], cell["row"], 1,
                               pixels["grid"]["marker_cells"])
        landing = (column - 1) if column else None
        ink = ink_cells(images[page], grids[page], cell["ink_row"], 1, 9)
        appearance, appearance_distance = classify(cell)
        results.append({
            "id": cell["id"], "class": cell["class"],
            "strategy": cell["strategy"], "claim": cell["claim"],
            "advance": cell["advance"], "landing": landing, "ink": ink,
            "appearance": appearance,
            "appearance_distance": appearance_distance,
        })

    dsr = {(r["id"], r["strategy"]): r for r in manifest["dsr"]}
    for row in results:
        measured = dsr.get((row["id"], row["strategy"]))
        if measured:
            row["wrapped_at_claim"] = measured.get("wrapped_at_claim")
            row["wrapped_at_advance"] = measured.get("wrapped_at_advance")

    document = {"stamp": manifest.get("stamp", {}), "results": results}
    with open(arguments.output, "w") as handle:
        json.dump(document, handle, indent=1, sort_keys=True)

    print(f"{len(results)} cells -> {arguments.output}")
    print(f"{'id':20}{'strategy':10}{'adv':>4}{'land':>5}{'ink':>4}"
          f"{'wrapS':>6}  appearance")
    for row in results:
        print(f"{row['id']:20}{row['strategy']:10}{row['advance']:4}"
              f"{str(row['landing']):>5}{str(row['ink']):>4}"
              f"{str(row.get('wrapped_at_advance')):>6}  {row['appearance']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
