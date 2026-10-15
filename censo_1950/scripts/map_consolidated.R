# Build state maps from approved consolidated totals and INEGI 2025 boundaries.
suppressPackageStartupMessages(library(sf))
suppressPackageStartupMessages(library(ggplot2))
case <- "censo_1950/data"
out <- read.csv(file.path(case, "consolidated/census_long.csv"),
                encoding = "UTF-8", colClasses = "character")
geo <- st_read(file.path(case, "raw/geo/mexico_states_2025_simplified.geojson"), quiet = TRUE)
cw <- read.csv(file.path(case, "geographic_crosswalk.csv"), encoding = "UTF-8",
               colClasses = "character")
keys <- cw[cw$geographic_level_proposal == "state", c("pdf_page", "printed_row_start", "cve_ent")]
out$printed_row_start <- as.character(((as.integer(out$printed_row) - 1L) %/% 5L) * 5L + 1L)
out$cve_ent <- keys$cve_ent[match(paste(out$pdf_page, out$printed_row_start),
                                    paste(keys$pdf_page, keys$printed_row_start))]
tot <- out[out$geographic_level == "state" & out$holding == "total", ]
metric <- function(variable) {
  x <- tot[tot$variable == variable, c("cve_ent", "value_final", "value_origin")]
  names(x)[2:3] <- c(variable, paste0(variable, "_origin"))
  x
}
wide <- Reduce(function(x, y) merge(x, y, by = "cve_ent", all = TRUE), list(
  metric("vacunos_cabezas_suma"), metric("vacunos_cabezas_fino"),
  metric("vacunos_valor_suma")))
wide$heads <- as.numeric(wide$vacunos_cabezas_suma)
wide$value_per_head <- as.numeric(wide$vacunos_valor_suma) / wide$heads
wide$fine_share <- as.numeric(wide$vacunos_cabezas_fino) / wide$heads
review <- read.csv(file.path(case, "review/author_review.csv"), colClasses = "character")
pending_cells <- out[out$holding == "total" & out$cell %in% review$cell, ]
wide$pending <- wide$cve_ent %in% pending_cells$cve_ent
wide$value_per_head[wide$pending] <- NA_real_
wide$fine_share[wide$pending] <- NA_real_
wide$heads[wide$pending] <- NA_real_
map_data <- merge(geo, wide, by = "cve_ent", all.x = TRUE)
plot_metric <- function(column, title, legend) {
  ggplot(map_data) + geom_sf(aes(fill = .data[[column]]), colour = "white", linewidth = 0.2) +
    scale_fill_gradient(low = "#f4e7bf", high = "#9d2d22", na.value = "grey70",
                        name = legend) +
    labs(title = title, caption = "Grey: pending author review. INEGI 2025 boundaries.") +
    theme_void(base_size = 10) + theme(plot.title = element_text(face = "bold"),
      plot.caption = element_text(size = 7), legend.position = "bottom")
}
plots <- list(heads = plot_metric("heads", "Cattle heads", "Heads"),
  value_per_head = plot_metric("value_per_head", "Census value per head", "Pesos per head"),
  fine_share = plot_metric("fine_share", "Fine cattle share", "Share of heads"))
dir.create(file.path(case, "consolidated"), showWarnings = FALSE)
for (nm in names(plots)) ggsave(file.path(case, "consolidated", paste0("map_", nm, ".png")),
  plots[[nm]], width = 7, height = 5, dpi = 180)
invisible(plots)
