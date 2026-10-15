# Blind readings -> automatic decisions under the signed R2-R4 policy.
case_dir <- "censo_1950/data"
read <- function(path) read.csv(file.path(case_dir, path), encoding = "UTF-8", colClasses = "character", check.names = FALSE)
long <- read("extracted/long.csv")
long$cell <- paste(long$pdf_page, long$printed_row, long$printed_column, sep = ":")
checks <- read("review/check_results.csv")
policy <- read("check_policy.csv")
rounds <- c("review/reread", if (file.exists(file.path(case_dir, "review/reread_key_round2.csv"))) "review/reread_round2"); key_files <- c("review/reread_key.csv", if (length(rounds) == 2) "review/reread_key_round2.csv")
read_rounds <- function(files) do.call(rbind, lapply(files, read))
key <- read_rounds(key_files); claude <- read_rounds(file.path(rounds, "claude_readings.csv"))
codex <- read_rounds(file.path(rounds, "codex_readings.csv")); queue <- read_rounds(file.path(rounds, "queue.csv"))
if (anyDuplicated(long$cell) || anyDuplicated(key$reread_id) || anyDuplicated(claude$reread_id) || anyDuplicated(codex$reread_id) || !setequal(key$reread_id, queue$reread_id) || !setequal(key$reread_id, claude$reread_id) || !setequal(key$reread_id, codex$reread_id)) stop("Reread keys, queues, and paired readings must match one-to-one")
if (!all(policy$status[match(paste0("decision_", c("R1", "R2", "R3", "R4", "R5", "QA", "rounds", "printed", "cell_amendment")), policy$policy_id)] == "approved_from_author_chat")) stop("Signed reread rules are missing from check_policy.csv")
round_limit <- as.integer(sub("max_rounds=", "", policy$parameter[policy$policy_id == "decision_rounds"]))
if (length(round_limit) != 1 || is.na(round_limit) || round_limit > 5) stop("Invalid decision round limit")
key <- key[match(queue$reread_id, key$reread_id), ]
key$cell_index <- match(key$cell, long$cell)
if (anyNA(key$cell_index)) stop("A reread key points to an unknown cell")
key$claude <- trimws(claude$reading[match(key$reread_id, claude$reread_id)])
key$codex <- trimws(codex$reading[match(key$reread_id, codex$reread_id)])
key$claude <- ifelse(tolower(key$claude) %in% c("blank", "illegible"), tolower(key$claude), key$claude); key$codex <- ifelse(tolower(key$codex) %in% c("blank", "illegible"), tolower(key$codex), key$codex)
valid_reading <- function(x) grepl("^[0-9]+$", x) | x %in% c("blank", "illegible")
if (!all(valid_reading(key$claude)) || !all(valid_reading(key$codex))) stop("Unexpected reading; use a number, blank, or illegible")
number <- function(x) if (!is.na(x) && grepl("^[0-9]+$", x)) as.numeric(x) else NA_real_
key$claude_n <- vapply(key$claude, number, 0.0); key$codex_n <- vapply(key$codex, number, 0.0)
cell_sets <- strsplit(checks$cells, "|", fixed = TRUE)
identity_sets <- function(cell, id) {
  hit <- which(checks$check_id == id & vapply(cell_sets, function(x) cell %in% x, logical(1)))
  if (!length(hit)) return(character()); if (length(hit) != 1) stop(paste("Expected one", id, "identity for", cell))
  cell_sets[[hit]]
}
axes <- lapply(long$cell, function(cell) list(fino_corriente = identity_sets(cell, "fino_corriente"), holding_total = identity_sets(cell, "holding_total")))
names(axes) <- long$cell
initial_status <- function(cell, id) { hit <- which(checks$check_id == id & vapply(cell_sets, function(x) cell %in% x, logical(1))); if (!length(hit)) "not_evaluated" else checks$status[hit] }
numeric_read <- function(x) !is.na(x) && is.finite(x) && x >= 0
state <- as.numeric(long$value); names(state) <- long$cell
ocr_n <- suppressWarnings(as.numeric(long$value[key$cell_index]))
triple <- !is.na(ocr_n) & !is.na(key$claude_n) & !is.na(key$codex_n) & key$claude_n == ocr_n & key$codex_n == ocr_n
any_ocr <- !is.na(ocr_n) & ((!is.na(key$claude_n) & key$claude_n == ocr_n) | (!is.na(key$codex_n) & key$codex_n == ocr_n))
active <- key$reason != "qa" & !(key$reason == "author_review_identity" & any_ocr)
queued_cells <- key$cell[active]
confirmed <- !is.na(state) & !(long$cell %in% queued_cells); names(confirmed) <- long$cell
state[queued_cells] <- NA_real_
axis_fit <- function(cell, id, value) {
  if (!numeric_read(value)) return(FALSE)
  members <- axes[[cell]][[id]]; if (!length(members)) return(NA); other <- setdiff(members, cell)
  prov <- other[!confirmed[other] & other %in% names(agreed)]; if (any(!confirmed[setdiff(other, prov)])) return(NA)
  vals <- state[members]; vals[match(prov, members)] <- agreed[prov]; vals[match(cell, members)] <- value
  if (anyNA(vals)) NA else vals[1] == sum(vals[-1])
}
both_fit <- function(cell, value) {
  z <- c(axis_fit(cell, "fino_corriente", value), axis_fit(cell, "holding_total", value))
  if (anyNA(z)) NA else all(z)
}
same_read <- function(a, b) { an <- number(a); bn <- number(b); if (!is.na(an) || !is.na(bn)) !is.na(an) && !is.na(bn) && an == bn else identical(a, b) }
matches_ocr <- function(reading, i) {
  n <- number(reading)
  o <- number(long$value[i]); if (!is.na(o)) return(if (!is.na(n) && n == o) "yes" else "no")
  if (long$value_origin[i] == "blanco") if (reading == "blank") "yes" else "no" else "not_comparable"
}
implied_value <- function(cell, id) {
  members <- axes[[cell]][[id]]; pos <- match(members, long$cell)
  if (anyNA(pos) || any(!confirmed[members[members != cell]])) return(NA_real_)
  vals <- state[members]; parent <- if (id == "fino_corriente") long$tipo[pos] == "suma" else long$holding[pos] == "total"
  p <- which(parent); target <- match(cell, members); parts <- setdiff(seq_along(members), p); if (length(p) != 1) return(NA_real_)
  if (target == p) sum(vals[parts]) else vals[p] - sum(vals[setdiff(parts, target)])
}
# Joint R2: matching readings of other queued cells count as provisional values.
ag <- which(active & mapply(same_read, key$claude, key$codex) & !is.na(key$claude_n)); agreed <- setNames(key$claude_n[ag], key$cell[ag])
decisions <- list(); cell_decisions <- list()
# Author review (export of the review tool): signed values are confirmed before the rules run again.
author_file <- file.path(case_dir, "review/author_review_export.csv")
if (file.exists(author_file)) {
  au <- read.csv(author_file, encoding = "UTF-8", colClasses = "character", check.names = FALSE, fileEncoding = "UTF-8-BOM")
  au$author_rule <- ""; au$date <- ""; au$decided_by <- ""; am_file <- file.path(case_dir, "review/author_review_amendments.csv")
  # An amendment row carries its own date and, optionally, who decided it.
  am_cell <- NULL
  if (file.exists(am_file)) { am <- read.csv(am_file, encoding = "UTF-8", colClasses = "character", check.names = FALSE)
    if (!"decided_by" %in% names(am)) am$decided_by <- ""
    # Policy decision_cell_amendment: an obs_id written as page:row:column is a cell the author checked against the image without a reread.
    is_cell <- grepl("^[0-9]+:[0-9]+:[0-9]+$", am$obs_id); am_cell <- am[is_cell, ]; am <- am[!is_cell, ]
    cols <- c("obs_id", "valor_manual", "legibilidad_manual", "notas_manual", "author_rule", "date", "decided_by")
    au <- au[!au$obs_id %in% am$obs_id, ]; au <- rbind(au[, cols], am[, cols]) }
  signed_date <- c(); signed_by <- c()
  au <- au[grepl("^[0-9]+$", au$valor_manual), ]; k <- match(au$obs_id, key$reread_id)
  if (anyNA(k)) stop("Author review refers to an unknown reread_id")
  for (j in seq_len(nrow(au))) {
    i <- k[j]; cell <- key$cell[i]; v <- as.numeric(au$valor_manual[j]); o <- ocr_n[i]
    src <- if (!is.na(o) && v == o) "OCR" else if (!is.na(key$claude_n[i]) && v == key$claude_n[i]) "Claude reading" else if (!is.na(key$codex_n[i]) && v == key$codex_n[i]) "Codex reading" else "manual value"
    state[cell] <- v; confirmed[cell] <- TRUE
    if (nzchar(au$date[j])) signed_date[cell] <- au$date[j]
    if (nzchar(au$decided_by[j])) signed_by[cell] <- au$decided_by[j]
    decisions[[length(decisions) + 1]] <- data.frame(cell = cell, ocr_literal = long$literal_value[key$cell_index[i]],
      ocr_value = long$value[key$cell_index[i]], claude_reading = key$claude[i], codex_reading = key$codex[i], decided_value = v,
      value_origin = if (src == "OCR") long$value_origin[key$cell_index[i]] else "revision_autor",
      rule_id = if (nzchar(au$author_rule[j])) au$author_rule[j] else "author_review",
      evidence = trimws(paste0("Author checked the page and kept the ", src, ". ", au$notas_manual[j])), stringsAsFactors = FALSE)
  }
  # Cell amendments set the value before the rules run; their decisions are appended last so earlier decision IDs do not move.
  for (j in seq_len(NROW(am_cell))) {
    cell <- am_cell$obs_id[j]; i <- match(cell, long$cell); v <- as.numeric(am_cell$valor_manual[j])
    if (is.na(i)) stop(paste("Cell amendment refers to an unknown cell:", cell))
    if (cell %in% key$cell) stop(paste("Cell", cell, "has a reread key; amend it by reread_id"))
    if (is.na(v)) stop(paste("Cell amendment without a numeric value:", cell))
    state[cell] <- v; confirmed[cell] <- TRUE
    if (nzchar(am_cell$date[j])) signed_date[cell] <- am_cell$date[j]
    if (nzchar(am_cell$decided_by[j])) signed_by[cell] <- am_cell$decided_by[j]
    cell_decisions[[length(cell_decisions) + 1]] <- data.frame(cell = cell, ocr_literal = long$literal_value[i],
      ocr_value = long$value[i], claude_reading = "", codex_reading = "", decided_value = v, value_origin = "revision_autor",
      rule_id = if (nzchar(am_cell$author_rule[j])) am_cell$author_rule[j] else "author_review",
      evidence = trimws(paste0("Author checked the page against the image (cell without reread). ", am_cell$notas_manual[j])), stringsAsFactors = FALSE)
  }
}
for (round in seq_len(round_limit)) {
  proposals <- list()
  for (i in which(active & !confirmed[key$cell])) {
    cell <- key$cell[i]; a <- key$claude_n[i]; b <- key$codex_n[i]
    fa <- both_fit(cell, a); fb <- both_fit(cell, b); rule <- ""; value <- NA_real_
    if (same_read(key$claude[i], key$codex[i]) && numeric_read(a) && isTRUE(fa)) { rule <- "R2"; value <- a }
    else if (!same_read(key$claude[i], key$codex[i]) && !is.na(fa) && !is.na(fb) && xor(isTRUE(fa), isTRUE(fb))) {
      rule <- "R3"; value <- if (isTRUE(fa)) a else b
    } else if (identical(fa, FALSE) && identical(fb, FALSE)) {
      ocr <- as.numeric(long$value[key$cell_index[i]])
      same_as_ocr <- (!is.na(ocr) && !is.na(a) && !is.na(b) && a == ocr && b == ocr) ||
        (is.na(ocr) && long$value_origin[key$cell_index[i]] == "blanco" && key$claude[i] == "blank" && key$codex[i] == "blank")
      row_failed <- "fail" %in% initial_status(cell, "fino_corriente")
      col_failed <- "fail" %in% initial_status(cell, "holding_total")
      if (!(same_as_ocr && (row_failed || col_failed))) {
        r <- implied_value(cell, "fino_corriente"); c <- implied_value(cell, "holding_total")
        if (!is.na(r) && !is.na(c) && r == c && r >= 0 && isTRUE(both_fit(cell, r))) { rule <- "R4"; value <- r }
      }
    }
    if (nzchar(rule)) proposals[[length(proposals) + 1]] <- list(i = i, cell = cell, rule = rule, value = value)
  }
  if (!length(proposals)) break
  for (p in proposals) {
    i <- p$i; cell <- p$cell; state[cell] <- p$value; confirmed[cell] <- TRUE
    evidence <- switch(p$rule, R2 = "Readings agree; row and holding identities pass.",
      R3 = "arbitrated by arithmetic", R4 = "Both identities imply the same value from confirmed components.")
    decisions[[length(decisions) + 1]] <- data.frame(
      cell = cell, ocr_literal = long$literal_value[key$cell_index[i]],
      ocr_value = long$value[key$cell_index[i]], claude_reading = key$claude[i],
      codex_reading = key$codex[i], decided_value = p$value,
      value_origin = if (p$rule == "R4") "reconstruccion_aritmetica" else "vlm_confirmado",
      rule_id = p$rule, evidence = evidence, stringsAsFactors = FALSE)
  }
}
# Printed source discrepancy: OCR and both readings agree, identity gap below 1% of its total.
held <- which(active & !confirmed[key$cell] & triple); state[key$cell[held]] <- ocr_n[held]; confirmed[key$cell[held]] <- TRUE
gap <- function(cell, id) {
  members <- axes[[cell]][[id]]; if (!length(members)) return(0); if (any(!confirmed[members])) return(NA_real_)
  pos <- match(members, long$cell); parent <- if (id == "fino_corriente") long$tipo[pos] == "suma" else long$holding[pos] == "total"
  abs(state[members][parent] - sum(state[members][!parent])) / state[members][parent]
}
gap_note <- setNames(rep("", nrow(key)), key$cell)
for (i in held) {
  g <- c(gap(key$cell[i], "fino_corriente"), gap(key$cell[i], "holding_total"))
  gap_note[key$cell[i]] <- paste(ifelse(is.na(g), "unconfirmed members", sprintf("%.3f%%", 100 * g)), collapse = " / ")
  if (anyNA(g) || max(g) >= 0.01) { confirmed[key$cell[i]] <- FALSE; next }
  decisions[[length(decisions) + 1]] <- data.frame(cell = key$cell[i], ocr_literal = long$literal_value[key$cell_index[i]],
    ocr_value = long$value[key$cell_index[i]], claude_reading = key$claude[i], codex_reading = key$codex[i], decided_value = ocr_n[i],
    value_origin = long$value_origin[key$cell_index[i]], rule_id = "printed_source_discrepancy",
    evidence = sprintf("OCR and both readings agree; identity gap %.3f%% of total.", 100 * max(g)), stringsAsFactors = FALSE)
}
decisions <- c(decisions, cell_decisions)
# The author queue is stable: every active cell the automatic rules did not decide, with the author's decision beside it.
auto_cells <- unlist(lapply(decisions, function(d) if (!grepl("^Author", d$evidence)) d$cell))
author_dec <- do.call(rbind, c(list(data.frame(cell = character(), rule_id = character(), decided_value = character(), evidence = character())),
  lapply(decisions, function(d) if (grepl("^Author", d$evidence)) data.frame(cell = d$cell, rule_id = d$rule_id, decided_value = as.character(d$decided_value), evidence = d$evidence))))
residual <- which(active & !(key$cell %in% auto_cells))
rv <- function(x) if (length(residual)) x else character()
review <- data.frame(reread_id = key$reread_id[residual], cell = key$cell[residual],
  reason = key$reason[residual], image = queue$image[match(key$reread_id[residual], queue$reread_id)],
  ocr_literal = long$literal_value[key$cell_index[residual]], ocr_value = long$value[key$cell_index[residual]],
  claude_reading = key$claude[residual], codex_reading = key$codex[residual],
  fino_corriente_status = rv(vapply(key$cell[residual], function(c) initial_status(c, "fino_corriente"), "")),
  holding_total_status = rv(vapply(key$cell[residual], function(c) initial_status(c, "holding_total"), "")),
  triple_gap_row_holding = rv(unname(gap_note[key$cell[residual]])), author_decision = rv(author_dec$rule_id[match(key$cell[residual], author_dec$cell)]),
  author_value = rv(author_dec$decided_value[match(key$cell[residual], author_dec$cell)]),
  author_note = rv(author_dec$evidence[match(key$cell[residual], author_dec$cell)]), stringsAsFactors = FALSE)
if (length(decisions)) {
  decisions <- do.call(rbind, decisions); decisions$decision_id <- sprintf("D%03d", seq_len(nrow(decisions)))
  decisions$date <- ifelse(decisions$rule_id %in% c("printed_source_discrepancy", "author_review"), "2026-10-08", "2026-10-07")
  decisions$decided_by <- ifelse(decisions$rule_id == "author_review" | grepl("^Author", decisions$evidence), "Alexander Urrego-Mesa", paste0("rule ", decisions$rule_id, " (author-signed ", decisions$date, ")"))
  # Date and responsible person recorded in the amendment row take precedence.
  if (exists("signed_date") && length(signed_date)) {
    k <- match(names(signed_date), decisions$cell); decisions$date[k] <- unname(signed_date) }
  if (exists("signed_by") && length(signed_by)) {
    k <- match(names(signed_by), decisions$cell); decisions$decided_by[k] <- unname(signed_by) }
  decisions <- decisions[, c("decision_id", "cell", "ocr_literal", "ocr_value", "claude_reading", "codex_reading", "decided_value", "value_origin", "rule_id", "evidence", "decided_by", "date")]
} else decisions <- data.frame(decision_id=character(), cell=character(), ocr_literal=character(), ocr_value=character(), claude_reading=character(), codex_reading=character(), decided_value=character(), value_origin=character(), rule_id=character(), evidence=character(), decided_by=character(), date=character())
write.csv(decisions, file.path(case_dir, "decisions.csv"), row.names = FALSE, na = "", fileEncoding = "UTF-8")
write.csv(review, file.path(case_dir, "review/author_review.csv"), row.names = FALSE, na = "", fileEncoding = "UTF-8")
status_for <- function(cell, id, value) {
  if (!numeric_read(value)) return("not_evaluated"); z <- axis_fit(cell, id, value)
  if (is.na(z)) "not_evaluated" else if (z) "pass" else "fail"
}
agreement <- key
agreement$sample <- ifelse(agreement$reason == "qa", "qa", "queue")
agreement$readers_agree <- ifelse(mapply(same_read, agreement$claude, agreement$codex), "yes", "no")
agreement$claude_matches_ocr <- mapply(matches_ocr, agreement$claude, agreement$cell_index)
agreement$codex_matches_ocr <- mapply(matches_ocr, agreement$codex, agreement$cell_index)
agreement$claude_row_fit <- mapply(function(c, v) status_for(c, "fino_corriente", v), agreement$cell, agreement$claude_n)
agreement$codex_row_fit <- mapply(function(c, v) status_for(c, "fino_corriente", v), agreement$cell, agreement$codex_n)
agreement$claude_holding_fit <- mapply(function(c, v) status_for(c, "holding_total", v), agreement$cell, agreement$claude_n)
agreement$codex_holding_fit <- mapply(function(c, v) status_for(c, "holding_total", v), agreement$cell, agreement$codex_n)
agreement$who_matched_arithmetic <- mapply(function(ar, ah, br, bh) { a <- c(ar, ah); b <- c(br, bh); if (all(a == "pass") && all(b == "pass")) "both" else if (all(a == "pass")) "Claude" else if (all(b == "pass")) "Codex" else if (any(c(a, b) == "not_evaluated")) "not_evaluated" else "neither" }, agreement$claude_row_fit, agreement$claude_holding_fit, agreement$codex_row_fit, agreement$codex_holding_fit)
agreement <- agreement[, c("reread_id", "cell", "sample", "reason", "claude", "codex", "readers_agree", "claude_matches_ocr", "codex_matches_ocr", "claude_row_fit", "codex_row_fit", "claude_holding_fit", "codex_holding_fit", "who_matched_arithmetic")]
write.csv(agreement, file.path(case_dir, "review/reader_agreement.csv"), row.names = FALSE, na = "", fileEncoding = "UTF-8")
esc <- function(x) { x <- gsub("&", "&amp;", x, fixed = TRUE); x <- gsub("<", "&lt;", x, fixed = TRUE); x <- gsub(">", "&gt;", x, fixed = TRUE); gsub('"', "&quot;", x, fixed = TRUE) }
rows <- if (!nrow(review)) "<p>No cases remain for author review.</p>" else paste(vapply(seq_len(nrow(review)), function(i) paste0(
  "<tr><td><img width='280' src='reread/", esc(review$image[i]), "'></td><td>", esc(review$cell[i]),
  "<br>OCR: ", esc(review$ocr_literal[i]), "</td><td>Claude: ", esc(review$claude_reading[i]),
  "<br>Codex: ", esc(review$codex_reading[i]), "</td><td>Row: ", review$fino_corriente_status[i],
  "<br>Holding: ", review$holding_total_status[i], "</td></tr>"), ""), collapse = "\n")
html <- paste0("<!doctype html><meta charset='utf-8'><title>Author review</title><h1>Author review</h1><table border='1' cellpadding='6'><tr><th>Crop</th><th>Cell and OCR</th><th>Blind readings</th><th>Original identities</th></tr>", rows, "</table>")
writeLines(html, file.path(case_dir, "review/author_review.html"), useBytes = TRUE)
counts <- table(factor(decisions$rule_id, levels = c("author_review", "R2", "R3", "R4", "printed_source_discrepancy")))
qa_rows <- agreement[agreement$sample == "qa", ]
queue_rows <- agreement[agreement$sample == "queue", ]
qa_rate <- function(x) { comparable <- x != "not_comparable"; c(disagree = sum(x[comparable] == "no"), n = sum(comparable)) }
cat("Decisions by rule:", paste(names(counts), counts, collapse = "; "), "\nResidual:", nrow(review),
    "\nClaude-Codex agreement: queue", sum(queue_rows$readers_agree == "yes"), "/", nrow(queue_rows),
    "; QA", sum(qa_rows$readers_agree == "yes"), "/", nrow(qa_rows),
    "; overall", sum(agreement$readers_agree == "yes"), "/", nrow(agreement), "\nQA vs OCR Claude:",
    paste(qa_rate(qa_rows$claude_matches_ocr), collapse = "/"), "Codex:",
    paste(qa_rate(qa_rows$codex_matches_ocr), collapse = "/"), "\nRounds max:", round, "\n")
