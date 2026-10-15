"""Flatten frozen Textract cells and words, keeping OCR text and geometry.

Run from the repository root: python censo_1950/scripts/01_parse_textract.py
Input: data/extracted/textract/MEX_1950_C22_p162-165_textract.json.
Outputs: data/extracted/cells.csv and words.csv. No cleaning or row repair.
"""

import csv
import json
from collections import Counter, defaultdict
from pathlib import Path

CASE = Path(__file__).resolve().parents[1]
SOURCE = CASE / "data/extracted/textract/MEX_1950_C22_p162-165_textract.json"


def children(block, relationship="CHILD"):
    return [item for rel in block.get("Relationships", [])
            if rel["Type"] == relationship for item in rel["Ids"]]


def geometry(block):
    box = block["Geometry"]["BoundingBox"]
    return {key.lower(): box[key] for key in ("Left", "Top", "Width", "Height")}


def write_csv(path, rows):
    if not rows:
        raise ValueError(f"No records for {path.name}")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    raw = json.loads(SOURCE.read_text(encoding="utf-8"))
    if sorted(p["page_number"] for p in raw["pages"]) != [162, 163, 164, 165]:
        raise ValueError("Expected exactly PDF pages 162–165")
    cell_rows, word_rows = [], []
    for page in raw["pages"]:
        blocks = page["metadata"]["textract_blocks"]
        lookup = {block["Id"]: block for block in blocks}
        if len(lookup) != len(blocks):
            raise ValueError("Duplicate Textract block IDs")
        for block in blocks:
            for rel in block.get("Relationships", []):
                if any(item not in lookup for item in rel["Ids"]):
                    raise ValueError(f"Dangling relationship in {block['Id']}")
        memberships, merged = {}, defaultdict(list)
        word_cells = defaultdict(list)
        for order, table in enumerate(
                (b for b in blocks if b["BlockType"] == "TABLE"), 1):
            for item in children(table):
                if lookup[item]["BlockType"] == "CELL":
                    if item in memberships:
                        raise ValueError("A CELL belongs to several TABLE blocks")
                    memberships[item] = (table["Id"], order)
            for merge_id in children(table, "MERGED_CELL"):
                for item in children(lookup[merge_id]):
                    merged[item].append(merge_id)
        cells = [b for b in blocks if b["BlockType"] == "CELL"]
        if set(memberships) != {c["Id"] for c in cells}:
            raise ValueError("CELL coverage does not match TABLE relationships")
        keys = [(memberships[c["Id"]][0], c["RowIndex"], c["ColumnIndex"])
                for c in cells]
        if len(keys) != len(set(keys)):
            raise ValueError("Duplicate OCR row/column within a table")
        common = {"source_json": SOURCE.relative_to(CASE).as_posix(),
                  "pdf_page": page["page_number"],
                  "printed_page": page["page_number"] - 1}
        for cell in cells:
            word_ids = children(cell)
            if any(lookup[item]["BlockType"] != "WORD" for item in word_ids):
                raise ValueError("Unexpected CELL child type; inspect the source")
            for item in word_ids:
                word_cells[item].append(cell["Id"])
            table_id, order = memberships[cell["Id"]]
            cell_rows.append({
                **common, "table_id": table_id, "table_order": order,
                "cell_id": cell["Id"], "ocr_row": cell["RowIndex"],
                "ocr_column": cell["ColumnIndex"],
                "row_span": cell.get("RowSpan", 1),
                "column_span": cell.get("ColumnSpan", 1),
                "literal_value": " ".join(lookup[i]["Text"] for i in word_ids),
                "word_ids": "|".join(word_ids),
                "merged_cell_ids": "|".join(merged[cell["Id"]]),
                "confidence": cell.get("Confidence", ""), **geometry(cell)})
        for word in (b for b in blocks if b["BlockType"] == "WORD"):
            word_rows.append({
                **common, "word_id": word["Id"], "literal_text": word["Text"],
                "cell_ids": "|".join(word_cells[word["Id"]]),
                "confidence": word.get("Confidence", ""), **geometry(word)})
    # CELL text joins the original WORD strings in their CHILD order.
    # WORD records also retain text not assigned to any CELL, without dropping it.
    write_csv(CASE / "data/extracted/cells.csv", cell_rows)
    write_csv(CASE / "data/extracted/words.csv", word_rows)
    print("cells by PDF page:", dict(Counter(r["pdf_page"] for r in cell_rows)))
    print(f"{len(cell_rows)} cells; {len(word_rows)} words; no cleaning or repair")


if __name__ == "__main__":
    main()
