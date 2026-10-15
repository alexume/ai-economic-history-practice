"""Build a shuffled, blind reread queue and context crops from the census pages."""

import csv
import argparse
import random
import statistics
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "censo_1950" / "data"
REVIEW = DATA / "review"
SEED = 1950


def read_csv(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def cell_key(row):
    return f"{row['pdf_page']}:{row['printed_row']}:{row['printed_column']}"


def median_pitch(centres):
    ordered = sorted(set(centres))
    gaps = [b - a for a, b in zip(ordered, ordered[1:]) if b > a]
    if not gaps:
        raise ValueError("Cannot infer a context pitch from the mapped cells")
    return statistics.median(gaps)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--round", type=int, choices=(1, 2), default=1)
    round_number = parser.parse_args().round
    out = REVIEW / ("reread" if round_number == 1 else "reread_round2")
    key_path = REVIEW / ("reread_key.csv" if round_number == 1 else "reread_key_round2.csv")
    long = read_csv(DATA / "extracted" / "long.csv")
    by_key = {cell_key(row): row for row in long}
    if round_number == 1:
        alarm_cells = read_csv(REVIEW / "alarm_cells.csv")
        alarms = {row["cell"] for row in alarm_cells}
        candidates = {row["cell"] for row in alarm_cells if row["candidate"].upper() == "TRUE"}
        pending = {key for key, row in by_key.items() if row["value_origin"] == "pendiente"}
        reasons = {key: "alarm" for key in candidates}
        reasons.update({key: "pendiente" for key in pending})
        qa = random.Random(SEED).sample(sorted(set(by_key) - alarms), 30)
        reasons.update({key: "qa" for key in qa})
        first_id = 1
    else:
        checks = read_csv(REVIEW / "check_results.csv")
        cases = read_csv(REVIEW / "author_review.csv")
        previously_read = {row["cell"] for row in read_csv(REVIEW / "reread_key.csv")}
        reasons = {}
        for case in cases:
            for check_id in ("fino_corriente", "holding_total"):
                hits = [row for row in checks if row["check_id"] == check_id and case["cell"] in row["cells"].split("|")]
                if len(hits) > 1:
                    raise ValueError(f"More than one {check_id} identity for {case['cell']}")
                if hits:
                    reasons.update({cell: "author_review_identity" for cell in hits[0]["cells"].split("|")})
        reasons = {cell: reason for cell, reason in reasons.items() if cell not in previously_read}
        if not reasons:
            raise ValueError("No unread cells remain in the review identities")
        first_id = 93
        qa = []
    items = sorted(reasons.items())
    random.Random(SEED).shuffle(items)

    if out.exists() or key_path.exists():
        raise FileExistsError("Reread output already exists; inspect it before replacing")
    out.mkdir(parents=True)
    centers = {}
    pages = {}
    for row in long:
        page, printed_row, col = row["pdf_page"], int(row["printed_row"]), int(row["printed_column"])
        if row["left"] and row["right"] and row["top"] and row["bottom"]:
            x = (float(row["left"]) + float(row["right"])) / 2
            y = (float(row["top"]) + float(row["bottom"])) / 2
            centers.setdefault(page, {"x": {}, "y": {}})
            centers[page]["x"].setdefault(col, []).append(x)
            centers[page]["y"].setdefault(printed_row, []).append(y)
        pages[page] = DATA / "raw" / f"MEX_1950_C22_pdf_p{page}.png"
    positions = {}
    for page, dims in centers.items():
        xs = {col: statistics.median(vals) for col, vals in dims["x"].items()}
        ys = {row: statistics.median(vals) for row, vals in dims["y"].items()}
        positions[page] = (xs, ys, median_pitch(xs.values()), median_pitch(ys.values()))

    queue_path = out / "queue.csv"
    with queue_path.open("w", encoding="utf-8", newline="") as queue_file, \
            key_path.open("w", encoding="utf-8", newline="") as key_file:
        queue_writer = csv.writer(queue_file)
        key_writer = csv.writer(key_file)
        queue_writer.writerow(["reread_id", "image"])
        key_writer.writerow(["reread_id", "cell", "reason"])
        for index, (key, reason) in enumerate(items, start=first_id):
            reread_id = f"R{index:03d}"
            row = by_key[key]
            page = row["pdf_page"]
            row_num, col_num = int(row["printed_row"]), int(row["printed_column"])
            xs, ys, col_pitch, row_pitch = positions[page]
            cx = (float(row["left"]) + float(row["right"])) / 2 if row["left"] else xs[col_num]
            cy = (float(row["top"]) + float(row["bottom"])) / 2 if row["top"] else ys[row_num]
            image = Image.open(pages[page]).convert("RGB")
            width, height = image.size
            x0 = max(0, round((cx - 1.5 * col_pitch) * width))
            x1 = min(width, round((cx + 1.5 * col_pitch) * width))
            y0 = max(0, round((cy - 1.5 * row_pitch) * height))
            y1 = min(height, round((cy + 1.5 * row_pitch) * height))
            crop = image.crop((x0, y0, x1, y1))
            draw = ImageDraw.Draw(crop)
            box = (round((cx - col_pitch / 2) * width) - x0,
                   round((cy - row_pitch / 2) * height) - y0,
                   round((cx + col_pitch / 2) * width) - x0,
                   round((cy + row_pitch / 2) * height) - y0)
            draw.rectangle(box, outline=(230, 25, 35), width=max(3, width // 900))
            image_name = f"{reread_id}.png"
            crop.save(out / image_name, optimize=True)
            queue_writer.writerow([reread_id, image_name])
            key_writer.writerow([reread_id, key, reason])

    brief = """# Blind reread instructions

Open only the assigned image. Read only the value inside the red box; use nearby
rows and columns only to locate it. Do not inspect any OCR output or other files,
compare another reader's answer, infer a value, or use arithmetic.

For each image, report the printed number without spaces, `blank`, or `illegible`.
Write `<reader>_readings.csv` in this folder with columns `reread_id,reading,note`,
one row per image. Use the ID from `queue.csv`; put any brief visual uncertainty
in `note`.
"""
    (out / "reading_brief.md").write_text(brief, encoding="utf-8")
    print(f"Queue: {len(items)} images; alarm={sum(v == 'alarm' for v in reasons.values())}, "
          f"pendiente={sum(v == 'pendiente' for v in reasons.values())}, qa={len(qa)}; "
          f"round={round_number}; ids=R{first_id:03d}-R{first_id + len(items) - 1:03d}")


if __name__ == "__main__":
    main()
