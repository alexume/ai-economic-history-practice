# A printed census table: plan, verify and consolidate

This case teaches verification and what a pipeline is. The instructor prepares
and tests it here, then reproduces selected steps alongside the slides. The
[task brief](encargo.md) says what is wanted; this recipe says how. It is the
single description of the pipeline: the course guide and the slides refer to it.
Progress and approvals are logged in the course logbook (`BITACORA.md`, in the
instructor's repository). Commit identifiers cited below also refer to that
repository.

## What is a pipeline?

A pipeline is a process made of steps. Each step is a script with one function
and explicit inputs and outputs; its outputs feed the next steps. Steps can be in
different languages. Author decisions enter as data files the scripts read, never
as code.

## Recipe

Scripts are numbered in the order of the whole process, whatever their language.
Letters mark the gates where the author decides. Paths are relative to `censo_1950/`.

| Step | Script or action | Consumes | Produces | Check before the next step |
|---|---|---|---|---|
| Geography preparation (stage 0, instructor only) | `preparacion/copy_mexico_states.R` (R) | Read-only INEGI 2025 boundaries and state crosswalk | Simplified state geometry, reduced crosswalk, `cve_ent` links and source hashes | 32 unique state codes join to the census crosswalk |
| 1 Literal parse | `scripts/01_parse_textract.py` (Python) | Frozen Textract JSON | `data/extracted/cells.csv`, `words.csv` | Four pages; every CELL and WORD kept; IDs and links valid; OCR text unchanged |
| 2 Mapping proposal | `scripts/02_propose_mapping.py` (Python) | Cells, words, column meanings | `data/review/row_mapping_proposal.csv`, `cell_mapping_proposal.csv` | Printed rows, headers and levels located; page 165's second table excluded; ambiguous positions flagged |
| **A Mapping** | Author reviews against the page images | Proposals, images | `data/mapping.csv`, `crosswalk.csv`, `geographic_crosswalk.csv`, `cell_mapping.csv` | Rows, columns, units and geography approved; every empty position has a status |
| **B Check policy** | Author decides before parsing numbers | Images, mapping, OCR errors seen | `data/ocr_rules.csv`, `data/check_policy.csv` | Every rule has a reason; blanks and symbols have a status; tolerance, routing and stop rule stated |
| 3 Long format | `scripts/03_long.R` (R) | Approved cell mapping, crosswalks, OCR rules | `data/extracted/long.csv` | One record per printed cattle cell; literal and numeric value separate; no silent loss or double assignment |
| 4 Checks | `scripts/04_checks.R` (R) | Long table, check policy | `data/review/check_results.csv`, `alarms.csv`, `alarm_cells.csv` | Applied and not-evaluated checks reported; alarms name the cells involved without guessing the wrong one |
| **C Alarm queue** | Author routes each alarm before any VLM call | Alarms, images | Destinations in `alarms.csv` | Reread, author review, mapping repair or source discrepancy; budget and stop rule applied |
| 5 Prepare reread | `scripts/05_prepare_reread.py` (Python) | Alarm queue, pending cells, QA sample, page images | Blind crop folders and reread keys | Crop IDs conceal cell identity, reason and OCR value |
| 6 Adjudicate | `scripts/06_adjudicate.R` (R) | Long table, reread files, decision policy, recorded author decisions | `data/decisions.csv`, reader agreement, author review | Automatic rules applied in rounds; author decisions integrated; any unresolved cases remain open |
| **D Decisions** | Author adjudicates the remaining queue | Original and proposed readings, image, author-review queue | Decisions in `data/review/author_review.csv`, integrated by step 6 into `data/decisions.csv` | Decision, evidence, author and date; unresolved cases stay unresolved |
| 7 Consolidate | `scripts/07_consolidate.R` (R) | Long table, integrated decisions, author-review status | `data/consolidated/census_long.csv`, rerun checks, state maps | Originals retained; only recorded decisions applied; any pending values stay empty (currently none) |
| 8 Report | `informe.qmd` (Quarto) | Runs, decisions, agreement, consolidated table and maps | `informe.html` | Counts and figures generated from project files |

Every value keeps its original literal and a `value_origin` label: `ocr`,
`ocr_normalizado`, `blanco`, `reconstruccion_aritmetica`, `vlm_confirmado`,
`revision_autor` or `pendiente`. No values remain `pendiente` in the current
consolidated table.

## Commands

Run from the repository root. Only implemented steps are listed.

```powershell
# Stage 0, instructor only (needs the original research files):
# Rscript preparacion/copy_mexico_states.R
python censo_1950/scripts/01_parse_textract.py
python censo_1950/scripts/02_propose_mapping.py
Rscript censo_1950/scripts/03_long.R
Rscript censo_1950/scripts/04_checks.R
```

After the author has routed alarms and the independent rereads have been
returned, continue with the decision and consolidation stages:

```powershell
python censo_1950/scripts/05_prepare_reread.py
Rscript censo_1950/scripts/06_adjudicate.R
Rscript censo_1950/scripts/07_consolidate.R
quarto render censo_1950/informe.qmd
```

The Textract OCR was run in May 2026; its raw JSON is frozen in
`data/extracted/textract/` and no API call is made. Source hashes are in
`data/raw/source_inventory.csv`.

The unnumbered `scripts/map_consolidated.R` is an auxiliary that builds state
maps from the consolidated totals; it is not a pipeline step.

## Step notes

**Literal parse.** Keeps every CELL, including headers and the out-of-scope second
table. `ocr_row` and `ocr_column` are Textract's assignments, not verified printed
positions. `literal_value` joins the child WORD texts; `words.csv` keeps every
WORD with its geometry, also words outside any cell.

**Why the page still matters.** On PDF page 162, Textract splits the national
*fino* total: `144 530` lands in OCR row 4 and `1` in row 5, while the page prints
`1 144 530`. In the *corriente* column, OCR row 5 holds `5 856 987`, which belongs
to the *Mayores de 5 hectáreas* row. Following OCR rows would put valid-looking
numbers in the wrong place. This was found while building the mapping against the
page, not by a check.

**Mapping proposal.** Anchors printed rows on the WORD positions of column 2 and
corrects for page tilt with a first-row slope; its grouping and distance
parameters are part of the method under review. Result: 190 printed rows and 1,140
cattle positions; each numeric word is assigned once. Five positions have no word
and are review cases, not source blanks. Column 2 values (all animals) are used
only as positions, never extracted or checked.

**Mapping approved (gate A, 7 October 2026).** The author checked the proposal
against the page images and approved it as `data/cell_mapping.csv`; the proposal
stays in `data/review/` as step 2's output. Three findings worth teaching:

- *Joined cells.* 20 positions take words from two Textract cells (e.g. the
  national `1 144 530`). The positional mapping joins them correctly.
- *Labels are not used.* 23 OCR sub-row labels drift into the neighbouring row at
  the left margin. The holding category comes from the position in the five-row
  block; the OCR label is kept only as a literal.
- *An empty position is not a blank.* Of five positions with no word, four are
  printed blanks (*suma* equals *corriente* on the page): `source_blank_confirmed`.
  The fifth, Sinaloa, *de 5 hectáreas o menos*, *fino* head, prints `2`, which
  Textract did not return: `not_read_by_ocr`, sent to the reread queue. Treating
  every empty position as a blank would have turned a printed 2 into NA.

The geographic crosswalk (`data/geographic_crosswalk.csv`: national block, five
regions, 32 entities) was written by the agent from the OCR labels, without a
script, and accepted by the author on 6 October 2026 after review. It keeps the OCR
label next to each name and region. Being hand-made, it is an author decision file,
not a reproducible derivative.

**Long format.** One record per approved position (1,140). Only the approved OCR
rules are applied. A literal that still does not parse stays NA with
`value_origin` `pendiente`; nothing is repaired. First run, 7 October 2026: 67
`ocr`, 1,053 `ocr_normalizado` (spaces removed), 4 `blanco`, 16 `pendiente`
(15 unreadable literals such as `I 790`, `] 423`, `123-316`, plus Sinaloa's 2).
No `O`, `L` or `G` rule fired. After the approved rule amendment, the second run
still has 1,140 records and the original literals unchanged: 1,120 `ocr`, 13
`ocr_normalizado`, 4 `blanco`, and 3 `pendiente` (the literals `"` and `R 575`,
plus Sinaloa's printed 2, which OCR did not read). Removing spaces now has origin
`ocr`; only an applied rule marked `ocr_normalizado` changes that origin.

**Checks.** Every check in `check_policy.csv` is applied and reported in
`check_results.csv`, including `not_evaluated` cases; an incomplete identity is
tested only as an upper bound. Failures go to `alarms.csv` with the cells involved
and empty columns for gate C. `alarm_cells.csv` counts, per cell, the failed row,
column and aggregation checks: a cell failing both its row identity (*suma* =
*fino* + *corriente*) and its column identity (total = four holdings) is a
*candidate*, not a verdict. First run: 151 alarms; 666 cells appear in some alarm,
because aggregation checks name many cells; 64 candidate cells (48 at a row and
column crossing, 16 unreadable); 12 alarms have no candidate and go to the author.
After the OCR-rule amendment: 156 alarms; 786 cells appear in some alarm; 62
candidate cells; 8 alarms have no candidate. The 13 newly readable values make
more arithmetic checks evaluable, so the alarm count can rise even as the
unreadable queue falls. `data/review/runs.csv` records both runs and the SHA-256
of the OCR rules used for each.

**Rereads and automatic adjudication (8 October 2026).** The round 1 queue has
92 rows: 59 alarm cells, 3 pending cells and 30 QA cells without alarms. Round 2
added 96 companion rows. Each queue row points to a cropped image of its target
cell, rather than a full page. Both readers read the 188 queued rows, for 376
individual readings. `06_adjudicate.R` recorded 39 automatic decisions: 19 R2,
18 R3 and 2 R4.

**Closure before author review (commit `4b2e014`, 8 October 2026).** The 26
cells sent to the author remained unresolved in that historical consolidated
table. Its checks reported 35 failures: 26 unreadable cells and nine other failed
identities outside the residue. Seven of those identities already failed in the
amended run; two appeared after R3 at `162:45:4` and R2 at `162:18:4`.
The stage's queue, decisions and `runs.csv` are preserved in that commit;
the nine identities are recorded in that commit's
`data/review/consolidated_unexpected_failures.csv`. These counts describe the
earlier stage, not the current result.

**Author review integrated (8 October 2026, `0a76aaa`).** All 26 cells were
reviewed: 7 keep OCR, 15 match Claude, 0 match only Codex and 4 are manual
values. These groups are exclusive, comparing `author_value` against OCR,
Claude and Codex in that order before assigning the manual group. The stable
26-row queue remains in `data/review/author_review.csv` as evidence of the
intervention. It no longer represents pending work.

**Current consolidation and report.** The table retains all 1,140 positions,
every OCR literal and original value, with 70 recorded decisions (39 automatic
and 31 from the author) and 0 pending values. All 818 identities pass.
Campeche 162:52:3 (D024) was first kept as a printed discrepancy and corrected
to 44 386 when the author re-checked the page (14 October 2026). The 16
identities that still failed pointed to five cells outside the reread queue
(Tabasco 163:3:3 and 163:3:5, Baja California Sur 163:29:5, San Luis Potosí
162:33:4 and 162:35:4); on 15 October the author checked them against the image
and found five OCR errors, not printed discrepancies (D066–D070, rule
`decision_cell_amendment`). Current counts come from `data/review/runs.csv`,
`data/decisions.csv`, `data/review/consolidated_check_results.csv` and
`data/consolidated/census_long.csv`. State maps use 2025 INEGI boundaries;
grey is the missing-value colour. All 32 state totals needed by these maps are
available; the embedded caption about pending review describes the earlier
conditional display rule. `informe.qmd` generates results from the project
files. `data/costs.csv` records official per-page pricing and an API-equivalent
per-row estimate; the slide reports the two-reader costs by round. Each queued
row is sent as a cropped image rather than a full page. These are estimates
rather than billed usage, since token logs are not preserved. Cost estimates
distinguish queued rows from readings by two agents.

**Check policy.** Spaces are removed and uppercase `O`→`0`, `L`→`1`, `G`→`6` are
replaced in numeric fields only, keeping the literal. Blanks are NA, never zero;
zero and negatives raise alarms. Identities are exact and evaluated only when all
components are present; otherwise they are `not_evaluated`. A multi-cell failure
does not point to one cell, so it goes to the author, not to a reread. Structural
shifts go back to mapping. A source that genuinely does not add up is recorded,
not altered. A component may be reconstructed as published total minus the other
confirmed components only with evidence on that component and a specific author
decision; it is labelled `reconstruccion_aritmetica`.

## In class

Proposed duration: about 20 minutes, pending rehearsal. The four gates stay in
the repository; in class they are told
as two decision moments: *before running* (A mapping + B check policy) and *after
the checks* (C alarm queue + D decisions).

1. Zoom and pipeline diagrams, once (3 min).
2. A decision is data: the slide, then the CSV in the repository (2 min).
3. The national block through the pipeline, live, with the page 162 error as the
   single worked case (10 min).
4. The alarm funnel: how many cells, how many alarms, how many reviewed (5 min).
   Almost everything reads well, so the source is revisited only where an alarm
   rings: that is the lesson on proportionality.

Every error shown comes from this case's own runs.
