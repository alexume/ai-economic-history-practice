# Join the two inputs with the separator decided in the CSV.
decision <- read.csv("hola_mundo/data/decision.csv", colClasses = "character")
hola <- readLines("hola_mundo/data/hola.txt")
mundo <- readLines("hola_mundo/data/mundo.txt")
dir.create("hola_mundo/salida", showWarnings = FALSE)
writeLines(paste0(hola, decision$separator, mundo), "hola_mundo/salida/saludo.txt")
