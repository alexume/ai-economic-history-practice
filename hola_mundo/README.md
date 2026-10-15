# Hello, world: inputs, decisions and outputs

The smallest pipeline in the course. R is the only requirement. This
folder is part of the course repository: a repository is a folder whose
history git records, not a synonym for GitHub.

## Recipe

| Script | Reads | Writes |
|---|---|---|
| `scripts/01_hola.R` | the word «hola» | `data/hola.txt` |
| `scripts/02_mundo.R` | the word «mundo» | `data/mundo.txt` |
| `scripts/03_saludo.R` | `data/hola.txt`, `data/mundo.txt`, `data/decision.csv` | `salida/saludo.txt` |

From the course root, in the terminal (the place where you type commands):

```sh
Rscript hola_mundo/scripts/01_hola.R
Rscript hola_mundo/scripts/02_mundo.R
Rscript hola_mundo/scripts/03_saludo.R
```

In RStudio or Positron, set the working directory to the course root and run
`source("hola_mundo/scripts/01_hola.R")`, and so on.

The repository holds only the scripts and the decision: the three files they
write are outputs, rebuilt by running the scripts, so they are not versioned.
Run `git status` now: it lists `data/hola.txt`, `data/mundo.txt` and
`salida/saludo.txt` as new, untracked files.

Open `salida/saludo.txt`: it says `hola mundo`. In the editor, change **only
the data row** of `data/decision.csv`: `" "` becomes `", "`, and update who
decided and the date. Run script 03 again: it now says `hola, mundo`. The
quotes keep the space inside the CSV field. Restore `" "` and run 03 to return
to the first greeting.

Each script does one thing. The first two produce the inputs of the third.
The decision is an input too: changing it changes the result without changing
the code. A commit saves a point in the history that can be reviewed; a branch
lets you propose changes before they join the accepted version.
