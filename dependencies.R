# ==============================================================================
# DEPENDENCY MANIFEST
# This file declares all packages the project needs.
# renv::snapshot() picks these up; CI and Docker install from the same list.
# ==============================================================================

# --- App runtime ---
library(shiny)            # web framework
library(shinydashboard)  # dashboard layout
library(tidyverse)       # data wrangling (dplyr, ggplot2, readr, purrr, ...)
library(lubridate)       # date parsing
library(scales)          # axis/label formatting
library(plotly)          # interactive charts
library(DT)              # interactive tables
library(cluster)         # silhouette diagnostics
library(cachem)          # cache backend for bindCache()

# --- Development / testing ---
library(testthat)        # unit + server tests
library(lintr)           # static code analysis