# 📊 Customer Segmentation Platform

> **Production-ready customer analytics in R** — RFM scoring, K-Means ML clustering, and an interactive Shiny dashboard for marketing, retention, and growth teams.

🚀 **Live demo:** [https://musanyaks.shinyapps.io/customer-segmentation/](https://musanyaks.shinyapps.io/customer-segmentation/)

[![CI](https://github.com/musanyaks/customer-segmentation-platform/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/musanyaks/customer-segmentation-platform/actions/workflows/ci.yml)
[![R Version](https://img.shields.io/badge/R-%E2%89%A5%204.1-276DC3?logo=r&logoColor=white)](https://www.r-project.org/)
[![Shiny](https://img.shields.io/badge/Shiny-Production%20Ready-blue?logo=rstudio&logoColor=white)](https://shiny.posit.co/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Docker](https://img.shields.io/badge/Docker-Supported-2496ED?logo=docker&logoColor=white)](#option-1--docker-recommended)

---

## 📑 Table of Contents

- [Overview](#-overview)
- [Key Features](#-key-features)
- [Methodology](#-methodology)
  - [RFM Segmentation](#1-rfm-segmentation-rule-based)
  - [K-Means Clustering](#2-k-means-clustering-ml-based)
- [Dashboard Tour](#-dashboard-tour)
- [Getting Started](#-getting-started)
- [Data Requirements](#-data-requirements)
- [Configuration](#%EF%B8%8F-configuration)
- [Project Structure](#-project-structure)
- [Deployment](#-deployment)
- [Production Hardening](#-production-hardening)
- [API & Extensibility](#-api--extensibility)
- [Troubleshooting](#-troubleshooting)
- [Roadmap](#-roadmap)
- [Contributing](#-contributing)
- [License](#-license)

---

## 🎯 Overview

This platform transforms raw transaction logs into **actionable customer segments** using two complementary approaches:

| Approach | Type | Best For |
|----------|------|----------|
| **RFM Scoring** | Rule-based, interpretable | Marketing campaigns, playbooks, stakeholder communication |
| **K-Means Clustering** | Unsupervised ML | Pattern discovery, value-tier identification (Platinum → Bronze) |

Built for analysts who need more than a notebook: it ships with data validation, diagnostics (elbow + silhouette), PCA visualization, segment playbooks, one-click CSV export, and a deployment-ready architecture.

**Tech stack:** R · Shiny · shinydashboard · tidyverse · plotly · cluster · DT

---

## ✨ Key Features

### 🔬 Analytics Engine
- **RFM scoring** — Recency, Frequency, Monetary quintile scoring (1–5) with 9 named segments (Champions, At Risk, Hibernating, ...)
- **K-Means clustering** — Log-transformed, standardized features; `nstart = 25` restarts for stable convergence
- **Cluster diagnostics** — Elbow curve + average silhouette width across k = 2..12, with best-k highlighting
- **PCA projection** — 2-D interactive cluster map with variance-explained axis labels
- **Auto-labeled tiers** — Clusters ranked by mean spend → Platinum / Gold / Silver / Bronze
- **CLV proxy** — Annualized value estimate (`monetary / tenure × 365`)

### 🖥️ Dashboard
- 6 tabs: Overview · RFM Analysis · ML Clustering · Segment Profiles · Customer Explorer · Data
- Live KPI value boxes (customers, revenue, AOV, segment count)
- Interactive plots: revenue donut, R×F bubble scatter, RFM heatmap, radar profiles, boxplots
- **Segment Playbook** — per-segment priority + recommended marketing actions
- Customer-level table with column filters, copy/CSV/Excel export buttons

### 🏭 Production Touches
- CSV upload with **column alias auto-detection** (`user_id` → `customer_id`, `revenue` → `amount`, ...)
- Multi-format date parsing (ymd / dmy / mdy + datetime variants), currency string cleaning
- Input validation with user-friendly error messages
- Built-in synthetic data generator for demos, testing, and CI
- 50 MB upload limit, reactive caching via `bindCache()`

---

## 🧮 Methodology

### 1. RFM Segmentation (Rule-Based)

Each customer is scored on three dimensions, computed at a configurable **analysis date** (default: day after the last transaction):

| Metric | Definition | Scoring |
|--------|-----------|---------|
| **Recency** | Days since last purchase | Quintile, inverted → most recent = 5 |
| **Frequency** | Total number of orders | Quintile → most frequent = 5 |
| **Monetary** | Total lifetime spend | Quintile → highest spend = 5 |

> Quintiles use `rank(ties.method = "first")` to guarantee balanced buckets even with heavy ties (common in frequency data).

Scores combine into 9 business segments:

| Segment | Rule | Interpretation |
|---------|------|----------------|
| 🏆 Champions | R≥4, F≥4, M≥4 | Best customers — reward & retain |
| 💎 Loyal Customers | F≥4 | Habitual buyers — grow share of wallet |
| 🌱 New Customers | R≥4, F≤2 | Recent first purchase — onboard fast |
| ✨ Promising | R≥4 | Recent shoppers — nurture to repeat |
| ⚠️ Need Attention | R=3 | Slipping — re-engage now |
| 🚨 At Risk | R≤2, F≥3 | Were frequent, now lapsing |
| 💸 Cannot Lose Them | R≤2, F≥4, M≥4 | High-value defectors — 1:1 outreach |
| 😴 About to Sleep | R≤2, M≥3 | Low activity, decent spend |
| ❄️ Hibernating | Else | Dormant — low-cost contact only |

### 2. K-Means Clustering (ML-Based)

**Feature engineering** — skewed monetary variables are log-transformed before standardization:

```
log_recency   = log1p(recency)
log_frequency = log1p(frequency)
log_monetary  = log1p(monetary)
→ z-score scaled matrix
```

**Model selection** — run diagnostics before committing to k:

- **Elbow method**: total within-cluster sum of squares vs. k
- **Silhouette width**: cluster cohesion/separation (higher = better); best k is auto-highlighted

**Cluster labeling** — clusters are ranked by mean monetary value and mapped to intuitive value tiers:

| Rank | Label |
|------|-------|
| 1 | Platinum |
| 2 | Gold |
| 3 | Silver |
| 4+ | Bronze (then Segment 5, 6, ...) |

**Optional feature**: include average order value (`log_aov`) via the settings checkbox to capture basket-size behavior.

---

## 🖥️ Dashboard Tour

| Tab | Contents |
|-----|----------|
| **Overview** | KPIs · customers-per-segment bar chart · revenue donut · Recency×Frequency bubble map (size = spend) |
| **RFM Analysis** | R×F heatmap (avg spend) · R/F/M histograms · full segment economics table |
| **ML Clustering** | k selector · elbow + silhouette diagnostics · PCA cluster map · cluster sizes · per-feature boxplots |
| **Segment Profiles** | Radar chart of normalized segment profiles · marketing playbook · segment economics (revenue share, CLV proxy) |
| **Customer Explorer** | Searchable/filterable customer table with export (copy / CSV / Excel) + download handler |
| **Data** | CSV upload · sample data loader · dataset summary · raw preview |

---

## 🚀 Getting Started

### Prerequisites

- **R ≥ 4.1** ([download](https://cloud.r-project.org/))
- RStudio (recommended) or any R environment

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/musanyaks/customer-segmentation-platform.git
cd customer-segmentation-platform

# 2. (Recommended) Restore the pinned environment
Rscript -e 'install.packages("renv"); renv::restore()'
```

Dependencies install automatically on first run if `renv` is not used:

```r
pkgs <- c("shiny", "shinydashboard", "tidyverse", "lubridate",
          "scales", "plotly", "DT", "cluster")
```

### Run the App

```r
# From R console
shiny::runApp("app.R")

# Or from terminal
Rscript -e 'shiny::runApp("app.R", port = 3838, host = "0.0.0.0")'
```

Open **http://localhost:3838** — the app boots with 2,000 synthetic customers so every feature works out of the box.

### Quick Start (3 steps)

1. **Data tab** → click *Load sample data* (or upload your CSV)
2. **Sidebar** → choose segmentation method: `RFM rules` or `K-Means (ML)`
3. **ML Clustering tab** → inspect elbow/silhouette, set k, explore the PCA map

---

## 📥 Data Requirements

### Input Schema

Upload a **CSV of transactions** — one row per order:

| Column | Type | Required | Description |
|--------|------|:--------:|-------------|
| `customer_id` | character / integer | ✅ | Unique customer identifier |
| `order_date` | date / datetime | ✅ | Transaction date |
| `amount` | numeric | ✅ | Order value (> 0) |

### Column Auto-Detection

Common aliases are mapped automatically (case-insensitive):

| Canonical | Accepted Aliases |
|-----------|-----------------|
| `customer_id` | `customer`, `cust_id`, `user_id`, `client_id`, `CustomerID` |
| `order_date` | `date`, `OrderDate`, `invoice_date`, `transaction_date`, `InvoiceDate` |
| `amount` | `sales`, `revenue`, `total`, `order_value`, `price`, `value` |

### Cleaning Rules (applied on upload)

- Dates parsed as `ymd HMS`, `ymd`, `dmy`, `mdy` (+ Excel serial numbers)
- Currency strings (`"$1,234.56"`) stripped to numeric
- Rows with missing dates, missing amounts, or `amount ≤ 0` are dropped
- Minimum **50 valid rows** required after cleaning

### Example CSV

```csv
customer_id,order_date,amount
C00001,2024-11-03,129.90
C00001,2025-01-18,84.50
C00002,2025-02-02,210.00
```

---

## ⚙️ Configuration

All tunables live at the top of `app.R`:

| Setting | Location | Default | Description |
|---------|----------|---------|-------------|
| Upload size | `options(shiny.maxRequestSize = ...)` | 50 MB | Max CSV upload |
| Sample customers | `generate_transactions(n_customers = ...)` | 2,000 | Synthetic dataset size |
| K-Means restarts | `run_kmeans(nstart = 25)` | 25 | Convergence stability |
| Diagnostics range | `diagnose_k(max_k = ...)` | 2–12 | k sweep for elbow/silhouette |
| Analysis date | `compute_rfm(analysis_date = ...)` | last txn + 1 | Reference date for recency |
| Random seed | `seed = 42` / `123` | fixed | Reproducibility |

---

## 📁 Project Structure

```
customer-segmentation-platform/
├── .Rprofile                  # Activates renv on R startup
├── .gitignore
├── .dockerignore
├── app.R                      # Complete application (UI + server + engines)
├── dependencies.R             # Package list for installs / deploys
├── Dockerfile                 # Container build (renv restore)
├── docker-compose.yml         # One-command local container run
├── LICENSE
├── README.md
├── renv.lock                  # Pinned dependencies (renv)
├── data/
│   └── generate_sample_data.R # Synthetic transaction generator
├── deploy/
│   └── shiny-server.conf      # Shiny Server config (Linux deployment)
├── renv/
│   └── activate.R             # renv bootstrap (library/ is gitignored)
├── tests/
│   ├── testthat.R
│   └── testthat/
│       ├── setup.R
│       ├── test-compute_rfm.R
│       ├── test-feature_matrix.R
│       ├── test-kmeans.R
│       ├── test-import.R
│       └── test-server.R
└── .github/
    └── workflows/
        └── ci.yml             # GitHub Actions CI
```

> The app is intentionally **single-file** for easy deployment to Posit Connect and shinyapps.io — no `global.R` / module splitting required. Continuous integration runs the `testthat` suite on every push via `.github/workflows/ci.yml`.

---

## 🚢 Deployment

### Option 1 — Docker (recommended)

```dockerfile
FROM rocker/shiny:4.4

RUN install2.r --error \
    shiny shinydashboard tidyverse lubridate scales plotly DT cluster

COPY app.R /srv/shiny-server/app.R
EXPOSE 3838

CMD ["R", "-e", "shiny::runApp('/srv/shiny-server/app.R', host='0.0.0.0', port=3838)"]
```

```bash
docker build -t customer-segmentation .
docker run -d -p 3838:3838 customer-segmentation

# or, with Docker Compose
docker compose up -d --build
```

### Option 2 — Posit Connect

```bash
# Requires rsconnect + account credentials
Rscript -e 'rsconnect::deployApp(".", appName = "customer-segmentation")'
```

Access control, authentication (SSO/LDAP), and usage metrics are managed via the Connect UI.

### Option 3 — shinyapps.io

Live deployment: [https://musanyaks.shinyapps.io/customer-segmentation/](https://musanyaks.shinyapps.io/customer-segmentation/)

```r
rsconnect::deployApp(".", appName = "customer-segmentation")
```

### Option 4 — Shiny Server (self-hosted Linux)

Copy `app.R` to `/srv/shiny-server/customer-segmentation/` and restart the service. Configure scaling and idle timeouts in `shiny-server.conf`.

---

## 🔒 Production Hardening

Before going live with real customer data:

- [ ] **Pin dependencies** — `renv::init()` and commit `renv.lock`
- [ ] **Replace sample data** — connect to your warehouse via `DBI`/`pool` + `dm`; wrap heavy queries in `bindCache()`
- [ ] **Add authentication** — Posit Connect permissions or [`shinymanager`](https://github.com/datastorm-open/shinymanager)
- [ ] **Add logging** — [`logger`](https://daroczig.github.io/logger/) for request/error telemetry
- [ ] **Schedule ETL** — pre-compute RFM tables nightly via `cron` + `Rscript`; serve cached results
- [ ] **HTTPS** — reverse proxy (nginx / Caddy) in front of Shiny Server
- [ ] **Resource limits** — size containers for `n_customers × features` memory footprint of `dist()` (scales O(n²)); consider `cluster::clara()` or sampling above ~50k customers

---

## 🔌 API & Extensibility

Core functions are pure and reusable outside Shiny:

```r
source("app.R")  # or extract functions into R/ modules

tx  <- read_csv("transactions.csv")
rfm <- compute_rfm(tx)                     # RFM scores + rule segments
mat <- feature_matrix(rfm)                 # scaled log-features
diag <- diagnose_k(mat, max_k = 8)         # elbow + silhouette table
km  <- run_kmeans(mat, k = 4)              # fitted kmeans object
```

**Common extensions:**

| Extension | Package | Effort |
|-----------|---------|--------|
| Probabilistic CLV (BG/NBD + Gamma-Gamma) | `BTYD` / `BTYDplus` | Medium |
| Cohort retention heatmaps | `tidyverse` + `plotly` | Low |
| UMAP / t-SNE cluster maps | `uwot` | Low |
| Hierarchical / GMM clustering | `mclust` | Medium |
| Automated email handoff | `blastula` + CRM API | Medium |

---

## 🛠️ Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `CSV must contain: customer_id, order_date, amount` | Unrecognized headers | Rename columns or extend `standardize_columns()` alias map |
| `Too few valid rows after cleaning` | Date parse failure / negative amounts | Check date format; ensure amounts > 0 |
| App slow on large data | `dist()` is O(n²) in silhouette | Reduce `max_k`, or sample customers for diagnostics |
| Clusters differ between runs | Seed changed | Keep `seed` fixed in `run_kmeans()` |
| `prcomp` error | Constant feature column | Usually a degenerate dataset (e.g., all customers have 1 order) |
| Upload fails silently | File > 50 MB | Raise `shiny.maxRequestSize` or switch to DB ingestion |

---

## 🗺️ Roadmap

- [x] RFM quintile engine with 9 segments
- [x] K-Means + elbow/silhouette diagnostics
- [x] PCA cluster visualization
- [x] CSV upload with schema auto-detection
- [ ] BG/NBD + Gamma-Gamma probabilistic CLV
- [ ] Cohort retention analysis tab
- [ ] Database connectors (Postgres, BigQuery, Snowflake)
- [ ] Scheduled segment refresh + Slack/email alerts
- [ ] A/B campaign tracking per segment
- [ ] `testthat` coverage ≥ 80%

---

## 🤝 Contributing

1. Fork the repo and create a feature branch: `git checkout -b feature/my-improvement`
2. Follow [tidyverse style](https://style.tidyverse.org/) — run `styler::style_file("app.R")` before committing
3. Add tests for new logic in `tests/testthat/` and run them with `Rscript -e 'testthat::test_dir("tests/testthat")'`
4. Open a PR with a clear description and screenshots for UI changes

---

## 📄 License

Distributed under the **MIT License**. See [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgements

- RFM methodology adapted from classic direct-marketing literature
- Built with [Shiny](https://shiny.posit.co/), [tidyverse](https://www.tidyverse.org/), [plotly](https://plotly.com/r/), and [DT](https://rstudio.github.io/DT/)

<p align="center">
  <sub>Made with ❤️ and R — if this project helps you, consider giving it a ⭐</sub>
</p>
