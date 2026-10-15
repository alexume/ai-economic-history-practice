"""Propose printed-row assignments from parsed WORD geometry, without correction.

Run from the root: python censo_1950/scripts/02_propose_mapping.py
Consumes cells.csv, words.csv and approved column meanings in mapping.csv.
Writes review/row_mapping_proposal.csv and cell_mapping_proposal.csv only.
Column 2 supplies positional anchors, never cattle values or arithmetic checks.
All assignments are pending author review; empty assignments are not source NA.
"""

import argparse
import csv
from collections import defaultdict
from pathlib import Path
from statistics import mean

CASE = Path(__file__).resolve().parents[1]


def read_csv(path):
    with path.open(encoding="utf-8", newline="") as stream:
        return list(csv.DictReader(stream))


def write_csv(name, rows):
    path = CASE / "data/review" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def group_y(words, gap):
    groups = []
    for word in sorted(words, key=lambda w: w["y"]):
        if not groups or word["y"] - groups[-1][-1]["y"] > gap:
            groups.append([])
        groups[-1].append(word)
    return groups


def join_literal(words):
    return " ".join(w["literal_text"] for w in sorted(words, key=lambda w: w["x"]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--word-gap", type=float, default=0.004)
    parser.add_argument("--review-distance", type=float, default=0.0035)
    args = parser.parse_args()
    cells = {c["cell_id"]: c for c in read_csv(CASE / "data/extracted/cells.csv")}
    columns = [c for c in read_csv(CASE / "data/mapping.csv")
               if c["include_in_cattle_long"] == "true"]
    if sorted(int(c["printed_column"]) for c in columns) != list(range(3, 9)):
        raise ValueError("Expected the six approved cattle columns 3–8")
    body = defaultdict(list)
    for word in read_csv(CASE / "data/extracted/words.csv"):
        ids = word["cell_ids"].split("|") if word["cell_ids"] else []
        if len(ids) > 1:
            raise ValueError("Ambiguous WORD parent: inspect before reconstruction")
        if not ids:
            continue  # Titles and page annotations remain in the parsed WORD file.
        cell = cells[ids[0]]
        if cell["table_order"] != "1" or int(cell["ocr_row"]) <= 3:
            continue  # Repeated headers and page 165's second table stay in raw CSV.
        body[word["pdf_page"]].append({
            **word, "column": int(cell["ocr_column"]),
            "ocr_row": cell["ocr_row"], "x": float(word["left"]) + float(word["width"]) / 2,
            "y": float(word["top"]) + float(word["height"]) / 2})
    row_output, cell_output = [], []
    for page, words in sorted(body.items()):
        anchors = group_y([w for w in words if w["column"] == 2], args.word_gap)
        if not anchors or len(anchors) % 5:
            raise ValueError(f"Page {page}: positional anchors do not form five-row blocks")
        centers = [mean(w["y"] for w in group) for group in anchors]
        anchor_x = mean(w["x"] for w in anchors[0])
        first = [group_y([w for w in words if w["column"] == c], args.word_gap)[0]
                 for c in range(2, 9)]
        points = [(mean(w["x"] for w in g), mean(w["y"] for w in g)) for g in first]
        mx, my = mean(x for x, y in points), mean(y for x, y in points)
        slope = sum((x - mx) * (y - my) for x, y in points) / sum((x - mx) ** 2 for x, y in points)
        assignments = defaultdict(list)
        for word in words:
            projected = word["y"] + slope * (anchor_x - word["x"])
            ranking = sorted((abs(projected - center), i) for i, center in enumerate(centers))
            distance, row = ranking[0]
            word["review_flag"] = (distance > args.review_distance
                                   or ranking[1][0] - distance < 0.002)
            assignments[row, word["column"]].append(word)
        for row in range(len(anchors)):
            labels = assignments[row, 1]
            entity = join_literal(assignments[row - row % 5, 1])
            common = {"pdf_page": page, "printed_row": row + 1,
                      "entity_label_ocr": entity, "holding_position": row % 5,
                      "status": "proposal_pending_author_review"}
            row_output.append({
                **common, "row_label_ocr": join_literal(labels),
                "anchor_y": centers[row], "page_slope": slope,
                "label_word_ids": "|".join(w["word_id"] for w in labels),
                "positional_anchor_word_ids": "|".join(w["word_id"] for w in anchors[row]),
                "review_flag": str(any(w["review_flag"] for w in labels)).lower()})
            for column in columns:
                col = int(column["printed_column"])
                members = sorted(assignments[row, col], key=lambda w: w["x"])
                ids = list(dict.fromkeys(w["cell_ids"] for w in members))
                cell_output.append({
                    **common, "printed_column": col, "variable": column["variable"],
                    "literal_value": join_literal(members),
                    "word_ids": "|".join(w["word_id"] for w in members),
                    "source_cell_ids": "|".join(ids),
                    "source_ocr_rows": "|".join(cells[i]["ocr_row"] for i in ids),
                    "review_flag": str(not members or any(w["review_flag"] for w in members)).lower(),
                    "assignment_state": "no_words_assigned" if not members else "words_assigned",
                    "left": min((float(w["left"]) for w in members), default=""),
                    "top": min((float(w["top"]) for w in members), default=""),
                    "right": max((float(w["left"]) + float(w["width"]) for w in members), default=""),
                    "bottom": max((float(w["top"]) + float(w["height"]) for w in members), default="")})
        print(f"PDF page {page}: {len(anchors)} proposed rows; slope {slope:.5f}")
    write_csv("row_mapping_proposal.csv", row_output)
    write_csv("cell_mapping_proposal.csv", cell_output)
    print(f"{len(row_output)} proposed rows; {len(cell_output)} cattle cells; "
          f"{sum(r['review_flag'] == 'true' for r in cell_output)} flagged assignments")


if __name__ == "__main__":
    main()
