#!/usr/bin/env Rscript
# ==============================================================================
# Generates data/sample_transactions.csv using the app's built-in generator.
# Run from project root:  Rscript data/generate_sample_data.R
# ==============================================================================

options(csp.testmode = TRUE)          # source app.R without launching Shiny
source("app.R")

dir.create("data", showWarnings = FALSE)

tx <- generate_transactions(n_customers = 2000, seed = 42)
out <- file.path("data", "sample_transactions.csv")
readr::write_csv(tx, out)

message("Wrote ", nrow(tx), " rows | ",
        dplyr::n_distinct(tx$customer_id), " customers -> ", out)