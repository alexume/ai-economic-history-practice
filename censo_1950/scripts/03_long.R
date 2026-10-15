# Step 3: approved cell mapping -> one long record per printed cattle cell.
#
# Run from the root: Rscript censo_1950/scripts/03_long.R
# Consumes data/cell_mapping.csv, crosswalk.csv, geographic_crosswalk.csv and
# ocr_rules.csv. Writes data/extracted/long.csv only.
# Applies the approved OCR rules and nothing else: a literal that still does not
# parse stays NA with value_origin "pendiente". No value is repaired here.

case_dir <- "censo_1950/data"
read <- function(name) read.csv(file.path(case_dir, name), encoding = "UTF-8",
                                colClasses = "character", check.names = FALSE)

cells <- read("cell_mapping.csv")
xw <- read("crosswalk.csv")
geo <- read("geographic_crosswalk.csv")
rules <- read("ocr_rules.csv")
rules <- rules[rules$status == "approved_from_author_chat", ]
rules <- rules[order(as.integer(rules$order)), ]

# Variable dimensions and holding categories, both from the approved crosswalk.
# Position 0 is the printed geographic total; 1-4 follow the printed order.
vars <- xw[xw$dimension == "variable", c("source_key", "elemento", "medida", "tipo", "unidad")]
holdings <- c("total", xw$normalized_label[xw$dimension == "componente"])
cells <- merge(cells, vars, by.x = "variable", by.y = "source_key")
cells$holding <- holdings[as.integer(cells$holding_position) + 1]

# Geography: each printed row falls inside one approved five-row block.
geo_key <- function(page, row) paste(page, (as.integer(row) - 1) %/% 5)
geo$key <- geo_key(geo$pdf_page, geo$printed_row_start)
g <- geo[match(geo_key(cells$pdf_page, cells$printed_row), geo$key), ]
cells$geography <- g$geography_label_proposal
cells$geographic_level <- g$geographic_level_proposal
cells$nom_estado <- g$nom_estado_proposal
cells$nom_region <- g$nom_region_proposal

# Apply the OCR rules in their approved order, recording which ones changed text.
normalize <- function(literal) {
  text <- literal
  applied <- character()
  for (i in seq_len(nrow(rules))) {
    pattern <- if (rules$pattern[i] == "whitespace") "\\s+" else rules$pattern[i]
    new <- gsub(pattern, rules$replacement[i], text)
    if (new != text) applied <- c(applied, rules$rule_id[i])
    text <- new
  }
  c(text = text, rules = paste(applied, collapse = "|"))
}
norm <- lapply(cells$literal_value, normalize)
cells$normalized_text <- vapply(norm, `[[`, "", "text")
cells$ocr_rules_applied <- vapply(norm, `[[`, "", "rules")

parses <- grepl("^[0-9]+$", cells$normalized_text)
cells$value <- NA_real_
cells$value[parses] <- as.numeric(cells$normalized_text[parses])
rule_origin <- function(applied) {
  if (applied == "") return("ocr")
  ids <- strsplit(applied, "|", fixed = TRUE)[[1]]
  origins <- rules$value_origin[match(ids, rules$rule_id)]
  if (any(origins == "ocr_normalizado", na.rm = TRUE)) "ocr_normalizado" else "ocr"
}
applied_origins <- vapply(cells$ocr_rules_applied, rule_origin, "")
cells$value_origin <- ifelse(
  cells$assignment_state == "source_blank_confirmed", "blanco",
  ifelse(!parses, "pendiente",
         applied_origins))

long <- cells[order(cells$pdf_page, as.integer(cells$printed_row),
                    as.integer(cells$printed_column)),
              c("pdf_page", "printed_row", "printed_column", "geography",
                "geographic_level", "nom_estado", "nom_region", "holding",
                "elemento", "medida", "tipo", "unidad", "variable",
                "literal_value", "normalized_text", "ocr_rules_applied", "value",
                "value_origin", "assignment_state", "word_ids", "left", "top",
                "right", "bottom")]

# Before writing: one record per approved position, none lost, literals intact.
stopifnot(nrow(long) == 1140,
          !anyDuplicated(long[, c("pdf_page", "printed_row", "variable")]),
          !anyNA(long$geography), !anyNA(long$holding),
          identical(sort(long$literal_value), sort(read("cell_mapping.csv")$literal_value)))

write.csv(long, file.path(case_dir, "extracted/long.csv"), row.names = FALSE,
          na = "", fileEncoding = "UTF-8")
print(table(long$value_origin))
