# AI for research in economic history: practice repository

Material for the doctoral course *AI for research in economic history: from
chatbots to agentic workflows* (Universitat de
Barcelona). The course was a live demonstration; this repository is for you to
try it afterwards.

| Folder | What it is |
|---|---|
| [hola_mundo/](hola_mundo/) | The smallest pipeline: inputs, a decision stored as data, and an output. Start here to practise git and GitHub. |
| [censo_1950/](censo_1950/) | A complete case: Table 22 of the 1950 Mexican agricultural census, from frozen OCR to checked, consolidated data, with every decision recorded. |

Run every command from this root folder.

## What you need

- **hola_mundo:** R.
- **censo_1950:** Python 3; R with the packages `sf`, `ggplot2`, `digest` and
  `knitr`; [Quarto](https://quarto.org) to render `informe.qmd`.
- An editor with a terminal (the course used VS Code) and git.

## Suggested practice

1. Clone this repository and run the three `hola_mundo` R scripts
   (see [hola_mundo/README.md](hola_mundo/README.md)).
2. Create a branch, change the decision row in `hola_mundo/data/decision.csv`,
   run script 03 again, and commit the change with a message that says why.
3. Open the census recipe ([censo_1950/README.md](censo_1950/README.md)) and
   run steps 01 to 07. The decisions in `censo_1950/data/decisions.csv` and the
   author amendments in `censo_1950/data/review/` rebuild the consolidated
   table; change one amendment row and see which checks move.

## Sources

The census pages are from INEGI, *Censo Agrícola, Ganadero y Ejidal 1950*
(Mexico), Table 22; state boundaries from INEGI (2025). Both are reused under
INEGI's free-use terms, with attribution. Commit identifiers and the logbook
cited in the case files belong to the instructor's working repository.
