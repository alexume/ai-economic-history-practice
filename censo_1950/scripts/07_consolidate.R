# Apply approved adjudications without changing the extracted table.
case <- "censo_1950/data"
read_case <- function(path) read.csv(file.path(case, path), encoding = "UTF-8",
                                     colClasses = "character", check.names = FALSE)
long <- read_case("extracted/long.csv")
long$cell <- paste(long$pdf_page, long$printed_row, long$printed_column, sep = ":")
decisions <- read_case("decisions.csv")
review <- read_case("review/author_review.csv")
if (nrow(long) != 1140 || anyDuplicated(long$cell)) stop("Unexpected long-table keys")
if (anyDuplicated(decisions$cell)) stop("More than one decision for a cell")
out <- long
out$value_original <- out$value
out$value_final <- out$value
out$decision_id <- ""
idx <- match(decisions$cell, out$cell)
if (anyNA(idx)) stop("A decision refers to a missing long-table cell")
out$value_final[idx] <- decisions$decided_value
out$value_origin[idx] <- decisions$value_origin
out$decision_id[idx] <- decisions$decision_id
residual <- review$cell[!nzchar(review$author_decision) &
                         !nzchar(review$author_value) & !nzchar(review$author_note)]
residual_idx <- match(residual, out$cell)
if (anyNA(residual_idx)) stop("An unresolved author-review cell is missing from the long table")
out$value_final[residual_idx] <- ""
out$value_origin[residual_idx] <- "pendiente"
out <- out[, c(setdiff(names(out), c("value", "value_original", "value_final",
                                    "decision_id")), "value_original", "value_final",
                      "decision_id")]
dir.create(file.path(case, "consolidated"), showWarnings = FALSE)
write.csv(out, file.path(case, "consolidated/census_long.csv"), row.names = FALSE,
          na = "", fileEncoding = "UTF-8")
status <- system2("Rscript", c("censo_1950/scripts/04_checks.R", "--input",
  "censo_1950/data/consolidated/census_long.csv", "--prefix", "consolidated",
  "--run-label", "consolidated"))
if (status != 0) stop("Parameterized checks failed")
checks <- read_case("review/consolidated_check_results.csv")
residual_checks <- checks[checks$status == "fail", ]
involved <- strsplit(residual_checks$cells, "|", fixed = TRUE)
touching_residue <- vapply(involved, function(x) any(x %in% residual), logical(1))
unexpected <- residual_checks[!touching_residue, ]
baseline <- read_case("review/check_results.csv")
baseline_fail <- baseline[baseline$status == "fail", ]
same_failure <- vapply(seq_len(nrow(unexpected)), function(i) any(
  baseline_fail$check_id == unexpected$check_id[i] &
  baseline_fail$scope == unexpected$scope[i] &
  baseline_fail$cells == unexpected$cells[i] &
  baseline_fail$difference == unexpected$difference[i]), logical(1))
unexpected$present_in_amended_run <- same_failure
unexpected$related_decision_ids <- vapply(unexpected$cells, function(cells) {
  ids <- decisions$decision_id[decisions$cell %in% strsplit(cells, "|", fixed = TRUE)[[1]]]
  paste(ids, collapse = "|")
}, character(1))
unexpected$related_decision_cells <- vapply(unexpected$cells, function(cells) {
  ids <- decisions$cell[decisions$cell %in% strsplit(cells, "|", fixed = TRUE)[[1]]]
  paste(ids, collapse = "|")
}, character(1))
unexpected$related_decided_values <- vapply(unexpected$related_decision_ids, function(ids) {
  selected <- decisions[decisions$decision_id %in% strsplit(ids, "|", fixed = TRUE)[[1]], ]
  paste(selected$decided_value, collapse = "|")
}, character(1))
write.csv(unexpected, file.path(case, "review/consolidated_unexpected_failures.csv"),
          row.names = FALSE, na = "", fileEncoding = "UTF-8")
source("censo_1950/scripts/map_consolidated.R")
cat("Consolidated", nrow(out), "cells;", nrow(decisions), "decisions;",
    length(residual), "pending;", sum(touching_residue),
    "failed checks touch residual cells;", nrow(unexpected),
    "other failed identities,", sum(same_failure),
    "already present in the amended run. Details: review/consolidated_unexpected_failures.csv\n")
