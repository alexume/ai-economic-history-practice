# Step 4: apply the approved check policy to the long table; raise alarms.
#
# Run from the root: Rscript censo_1950/scripts/04_checks.R
# Consumes data/extracted/long.csv and data/check_policy.csv.
# Writes data/review/check_results.csv (every check, including not evaluated)
# and data/review/alarms.csv (failures only, with empty columns for gate C).
# Optional --input, --prefix and --run-label reuse the same checks for a table;
# prefixed outputs are separate while every run is recorded in review/runs.csv.
# An alarm names the cells involved; it never says which one is wrong.

case_dir <- "censo_1950/data"
args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(flag, default) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) default else args[i + 1]
}
input_path <- arg_value("--input", file.path(case_dir, "extracted/long.csv"))
prefix <- arg_value("--prefix", "")
run_label <- arg_value("--run-label", ifelse(nzchar(prefix), prefix, "amended"))
long <- read.csv(input_path, encoding = "UTF-8", colClasses = "character")
policy <- read.csv(file.path(case_dir, "check_policy.csv"), encoding = "UTF-8",
                   colClasses = "character")
value_column <- if ("value_final" %in% names(long)) "value_final" else "value"
long$value <- as.numeric(long[[value_column]])
long$cell <- paste(long$pdf_page, long$printed_row, long$printed_column, sep = ":")
long$level_name <- ifelse(long$geographic_level == "state", long$nom_estado,
                          ifelse(long$geographic_level == "region", long$nom_region, "national"))
results <- list()
add <- function(check_id, scope, status, parent, children, cells) {
  results[[length(results) + 1]] <<- data.frame(
    check_id, scope, status, published = parent, sum_of_parts = children,
    difference = children - parent, n_cells = length(cells),
    cells = paste(cells, collapse = "|"))
}

# Cell checks: readable after the approved OCR rules, and positive.
for (i in which(long$value_origin == "pendiente"))
  add("numeric_readability", paste(long$geography[i], long$holding[i], long$variable[i]),
      "fail", NA, NA, long$cell[i])
for (i in which(long$value < 1))
  add("positive_values", paste(long$geography[i], long$variable[i]), "fail", NA, NA, long$cell[i])

# One printed record per geography, holding and variable.
key <- paste(long$geography, long$holding, long$variable)
for (k in unique(key[duplicated(key)]))
  add("one_printed_record", k, "fail", NA, NA, long$cell[key == k])

# Identity: parent = sum of parts. Complete support -> exact equality;
# incomplete support -> only the upper bound (observed parts <= parent).
identity <- function(check_id, scope, parent, parts) {
  cells <- c(parent$cell, parts$cell)
  if (nrow(parent) != 1 || nrow(parts) == 0)
    return(add(check_id, scope, "not_evaluated", NA, NA, cells))
  p <- parent$value
  if (!anyNA(p) && !anyNA(parts$value)) {
    s <- sum(parts$value)
    return(add(check_id, scope, if (s == p) "pass" else "fail", p, s, cells))
  }
  s <- sum(parts$value, na.rm = TRUE)
  if (is.na(p) || all(is.na(parts$value)))
    return(add(check_id, scope, "not_evaluated", p, NA, cells))
  add("upper_bounds", paste(check_id, scope), if (s <= p) "pass" else "fail", p, s, cells)
}

# suma = fino + corriente, within one printed row, heads and pesos separately.
for (g in split(long, paste(long$pdf_page, long$printed_row, long$medida)))
  identity("fino_corriente", paste(g$geography[1], g$holding[1], g$medida[1]),
           g[g$tipo == "suma", ], g[g$tipo != "suma", ])

# Published geographic total = sum of its four holding components.
for (g in split(long, paste(long$geography, long$variable)))
  identity("holding_total", paste(g$geography[1], g$variable[1]),
           g[g$holding == "total", ], g[g$holding != "total", ])

# Aggregation across levels, never mixing them: same holding and variable.
for (g in split(long, paste(long$holding, long$variable))) {
  scope <- paste(g$holding[1], g$variable[1])
  states <- g[g$geographic_level == "state", ]
  regions <- g[g$geographic_level == "region", ]
  national <- g[g$geographic_level == "national", ]
  for (r in regions$nom_region)
    identity("states_region", paste(r, scope), regions[regions$nom_region == r, ],
             states[states$nom_region == r, ])
  identity("regions_national", scope, national, regions)
  identity("states_national", scope, national, states)
}

results <- do.call(rbind, results)
routes <- setNames(policy$route, policy$policy_id)
results$policy_route <- routes[results$check_id]
results$policy_route[is.na(results$policy_route)] <- routes[["upper_bounds"]]
alarms <- results[results$status == "fail", ]
alarms$alarm_id <- sprintf("A%03d", seq_len(nrow(alarms)))
alarms$author_route <- rep("", nrow(alarms))  # gate C: reread, author_review, mapping or source_discrepancy
alarms$author_note <- rep("", nrow(alarms))

tag <- if (nzchar(prefix)) paste0(prefix, "_") else ""
write.csv(results, file.path(case_dir, paste0("review/", tag, "check_results.csv")), row.names = FALSE,
          na = "", fileEncoding = "UTF-8")
write.csv(alarms[, c("alarm_id", setdiff(names(alarms), "alarm_id"))],
          file.path(case_dir, paste0("review/", tag, "alarms.csv")), row.names = FALSE, na = "",
          fileEncoding = "UTF-8")
print(table(results$check_id, results$status))

# Per cell: how many failed checks of each kind involve it. A cell failing both
# its row identity and its column identity is a candidate, not a verdict.
kind <- c(numeric_readability = "unreadable", fino_corriente = "row",
          holding_total = "column", states_region = "aggregation",
          regions_national = "aggregation", states_national = "aggregation",
          upper_bounds = "bound", positive_values = "unreadable",
          one_printed_record = "structure")
involved <- do.call(rbind, lapply(seq_len(nrow(alarms)), function(i) data.frame(
  cell = strsplit(alarms$cells[i], "|", fixed = TRUE)[[1]],
  kind = kind[[alarms$check_id[i]]])))
per_cell <- as.data.frame.matrix(table(involved$cell, factor(involved$kind, levels = unique(kind))))
per_cell$candidate <- per_cell$unreadable > 0 | (per_cell$row > 0 & per_cell$column > 0)
per_cell <- cbind(long[match(rownames(per_cell), long$cell),
                       c("cell", "geography", "holding", "variable", "literal_value",
                         "value_origin")], per_cell)
write.csv(per_cell[order(!per_cell$candidate, per_cell$cell), ],
          file.path(case_dir, paste0("review/", tag, "alarm_cells.csv")), row.names = FALSE,
          fileEncoding = "UTF-8")

# Append an auditable run summary, including the exact OCR-rule version.
rules_path <- file.path(case_dir, "ocr_rules.csv")
rules_hash <- toupper(digest::digest(file = rules_path, algo = "sha256"))
candidate_cells <- per_cell$cell[per_cell$candidate]
alarm_cells <- strsplit(alarms$cells, "|", fixed = TRUE)
alarms_without_candidate <- sum(!vapply(alarm_cells, function(x)
  any(x %in% candidate_cells), logical(1)))
run <- data.frame(
  run_label = run_label,
  run_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  n_cells = nrow(long),
  n_pendiente = sum(long$value_origin == "pendiente"),
  n_alarms = nrow(alarms),
  n_candidates = sum(per_cell$candidate),
  n_alarms_without_candidate = alarms_without_candidate,
  ocr_rules_sha256 = toupper(rules_hash[1]),
  stringsAsFactors = FALSE
)
runs_path <- file.path(case_dir, "review/runs.csv")
if (file.exists(runs_path)) {
  runs <- read.csv(runs_path, encoding = "UTF-8", check.names = FALSE)
  if (!"run_label" %in% names(runs)) {
    runs$run_label <- c("first", "amended")[seq_len(min(2, nrow(runs)))]
    runs <- runs[, c("run_label", setdiff(names(runs), "run_label"))]
  }
  runs <- runs[runs$run_label != run_label, , drop = FALSE]
  runs <- rbind(runs, run[, names(runs), drop = FALSE])
} else runs <- run
write.csv(runs, runs_path, row.names = FALSE, na = "", fileEncoding = "UTF-8")
cat(nrow(long), "cells;", nrow(alarms), "alarms;", nrow(per_cell),
    "cells in some alarm;", sum(per_cell$candidate), "candidate cells\n")
