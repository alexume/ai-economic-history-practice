# Task brief: transcribing Table 22 of Mexico's 1950 agricultural census

Agreed by the author on 6 October 2026.

## Purpose

The transcription yields a livestock series by entity and type of holding,
comparable with other Mexican agricultural censuses. Teaching aim: show that a
printed table is transcribed with OCR and checked with the arithmetic the source
itself prints; a VLM is kept for the cells that raise an alarm. OCR and VLM are
complements: the cost of a VLM on whole pages is shown only for comparison.

## Source

*Tercer Censo Agrícola Ganadero y Ejidal 1950*, Resumen General, Table 22,
*Ganado, aves y colmenas*, first part. PDF pages 162–165 (printed 161–164).

- Original: `data/raw/MEX_1950_C22_pdf_pp162-165.pdf`
- OCR images (300 DPI): `data/raw/MEX_1950_C22_pdf_p16{2..5}.png`
- Hashes: `data/raw/source_inventory.csv`

Structure observed on p. 162: blocks of five rows (entity; *mayores de 5 hectáreas*;
*de 5 hectáreas o menos*; *ejidos*; *en las poblaciones*). Columns: total value in
pesos; cattle in head (*suma*, *fino*, *corriente*) and in pesos (*suma*, *fino*,
*corriente*). Page 165 closes this block at the top and starts the second part of
the table below; the second part is out of scope.

## Extractors

| Id | Extractor | Type | State |
|---|---|---|---|
| A | AWS Textract (TABLES) | Paid OCR | Run in May 2026; raw output frozen in `data/extracted/textract/`, not re-run |
| B | VLM, cell crops | Reread | Only for cells routed from the alarm queue, with a closed question |

A is the main route; B rereads only what the checks flag. The cost of a VLM on
whole pages is estimated for comparison, not run as a route.

Each extractor works only from the images or the PDF and does not see the other
extractions. Rows and columns are reconstructed here, from the raw output, and
assessed separately from text recognition.

## Output

One raw output per extractor, never overwritten. Then one common long table with:
PDF page, physical row and column, entity and sub-row as printed, variable, unit
(head or pesos), literal value and numeric value.

## Checks (alarms)

1. Missing or non-numeric cell.
2. *Suma* = *fino* + *corriente*, in head and in pesos.
3. Entity = sum of its four sub-rows.
4. Region = sum of its states; national = sum of regions.
5. Five rows per block and continuity of entities across pages.

An alarm does not correct anything: it opens a case in `data/review/`.

## Do not

- Apply an arithmetic correction without an identified erroneous component,
  supporting evidence and author adjudication. The author-approved exception
  dated 6 October 2026 permits a proposal of published total minus the other
  confirmed components, labelled `reconstruccion_aritmetica` and kept distinct
  from visual confirmation. An identity alone does not locate the error.
- Add up different levels (national, regional, state) or sub-rows with their total.
- Fill empty cells or convert units.

## Recorded author decisions — 6 October 2026

- [`data/mapping.csv`](data/mapping.csv) records column meanings. Only the six
  cattle variables enter the cattle long table and its checks. The broader
  livestock/poultry/beehive value is retained in the raw extraction as context.
  The block runs from Estados Unidos Mexicanos to Tlaxcala, first part only.
- [`data/crosswalk.csv`](data/crosswalk.csv) separates `elemento`, `medida`,
  `tipo` and `unidad`, and normalizes the four holding categories. Geographic
  labels, region membership and the encoding of `nom_estado`, `nom_region`
  and `mex` remain to be reviewed during construction of the geographic mapping.
- [`data/ocr_rules.csv`](data/ocr_rules.csv) permits space removal and uppercase
  `O` to `0`, `L` to `1`, `G` to `6` in numeric fields only. Original text and
  applied rules are retained.
- [`data/check_policy.csv`](data/check_policy.csv) records positive values only,
  blank as NA, exact arithmetic identities, applicable upper bounds, review
  routing and correction provenance. An incomplete identity is not evaluated;
  NA is never replaced with zero. Unresolved extraction cases return to the
  source. Structural failures require mapping review.

Column meanings and the initial policy are agreed. The physical cell mapping was
approved on 7 October 2026 (`data/cell_mapping.csv`); no cell-specific correction
or consolidated result is approved.
Each value will retain its original literal and a `value_origin` label.

## Stop when

Every cell of the block, on all four pages, has a value or a status, and the alarm
queue is built. Adjudication is a later step.

## Audit afterwards, not correction

A sample of cells without alarms is checked against the page to measure which
errors the checks let through. Errors shown in class come from these runs.
