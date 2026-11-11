# ==============================================================================
# CUSTOMER SEGMENTATION PLATFORM
# Production-ready R Shiny app: RFM + K-Means clustering + interactive dashboard
#
# Run: shiny::runApp("app.R")   (or open in RStudio -> "Run App")
# ==============================================================================

# ------------------------------------------------------------------------------
# 0. Packages
# ------------------------------------------------------------------------------

pkgs <- c("shiny", "shinydashboard", "tidyverse", "lubridate",
          "scales", "plotly", "DT", "cluster")
new  <- pkgs[!pkgs %in% rownames(installed.packages())]
if (length(new)) install.packages(new)

suppressPackageStartupMessages({
  library(shiny); library(shinydashboard); library(tidyverse)
  library(lubridate); library(scales); library(plotly)
  library(DT); library(cluster)
})

options(shiny.maxRequestSize = 50 * 1024^2)   # 50 MB upload limit
# Cache backend required by bindCache()
shinyOptions(cache = cachem::cache_mem(max_size = 256 * 1024^2))

# ------------------------------------------------------------------------------
# 1. Sample data generator (swap with your real data pipeline in production)
# ------------------------------------------------------------------------------
generate_transactions <- function(n_customers = 2000, seed = 42,
                                  end_date = Sys.Date()) {
  set.seed(seed)

  archetypes <- tibble(
    archetype  = c("champion", "loyal", "potential", "new", "at_risk", "hibernating"),
    weight     = c(0.10, 0.20, 0.25, 0.15, 0.15, 0.15),
    rate       = c(36, 22, 8, 2, 14, 4),        # expected orders / year
    spend_mu   = c(180, 120, 70, 60, 90, 45),   # avg order value
    recency_mu = c(10, 20, 45, 10, 160, 300)    # days since last order
  )

  customers <- tibble(
    customer_id = sprintf("C%05d", seq_len(n_customers)),
    archetype   = sample(archetypes$archetype, n_customers,
                         replace = TRUE, prob = archetypes$weight),
    signup_date = end_date - days(sample(90:1095, n_customers, replace = TRUE))
  ) %>%
    left_join(archetypes, by = "archetype") %>%
    mutate(
      tenure_days = as.numeric(end_date - signup_date),
      n_orders    = pmax(1, rpois(n(), rate * tenure_days / 365)),
      spend_mu    = rlnorm(n(), log(spend_mu), 0.3),
      last_order  = end_date - days(pmax(1, round(rnorm(n(), recency_mu, 15))))
    )

  customers %>%
    select(customer_id, n_orders, spend_mu, last_order) %>%
    rowwise() %>%
    mutate(orders = list({
      d <- sort(end_date - days(floor(runif(n_orders, 0, 365))))
      d[n_orders] <- max(last_order, min(d))
      tibble(
        order_id   = sprintf("O%08d", sample.int(1e8, n_orders)),
        order_date = as.Date(pmin(d, end_date)),
        amount     = round(rlnorm(n_orders, log(spend_mu), 0.25), 2)
      )
    })) %>%
    ungroup() %>%
    select(customer_id, orders) %>%
    unnest(orders) %>%
    arrange(customer_id, order_date)
}

# ------------------------------------------------------------------------------
# 2. Data import helpers
# ------------------------------------------------------------------------------
standardize_columns <- function(df) {
  nm <- names(df) %>%
    str_to_lower() %>%
    str_replace_all("[^a-z0-9]+", "_") %>%
    str_replace_all("^_|_$", "")
  aliases <- c(
    "customer" = "customer_id", "cust_id" = "customer_id", "user_id" = "customer_id",
    "client_id" = "customer_id", "customerid" = "customer_id",
    "date" = "order_date", "orderdate" = "order_date", "invoice_date" = "order_date",
    "transaction_date" = "order_date", "invoicedate" = "order_date",
    "sales" = "amount", "revenue" = "amount", "total" = "amount",
    "order_value" = "amount", "price" = "amount", "value" = "amount"
  )
  for (i in seq_along(nm)) if (nm[i] %in% names(aliases)) nm[i] <- aliases[[nm[i]]]
  names(df) <- nm
  df
}

parse_order_date <- function(x) {
  if (inherits(x, "Date")) return(x)
  if (is.numeric(x)) return(as.Date(x, origin = "1899-12-30"))
  suppressWarnings(
    parse_date_time(x, orders = c("ymd HMS", "ymd HM", "ymd", "dmy", "mdy",
                                  "dmy HMS", "mdy HMS")) %>% as.Date()
  )
}

# ------------------------------------------------------------------------------
# 3. RFM engine
# ------------------------------------------------------------------------------
compute_rfm <- function(tx, analysis_date = max(tx$order_date) + 1) {
  safe_ntile <- function(x, n = 5) {
    r <- rank(x, ties.method = "first")
    as.integer(ceiling(r / length(r) * n))
  }

  tx %>%
    group_by(customer_id) %>%
    summarise(
      first_purchase = min(order_date),
      last_purchase  = max(order_date),
      frequency      = n(),
      monetary       = sum(amount),
      .groups = "drop"
    ) %>%
    mutate(
      recency         = as.numeric(analysis_date - last_purchase),
      tenure_days     = pmax(as.numeric(analysis_date - first_purchase), 1),
      avg_order_value = monetary / frequency,
      annual_value    = monetary / tenure_days * 365,   # simple CLV proxy
      r_score = 6L - safe_ntile(recency),               # most recent = 5
      f_score = safe_ntile(frequency),
      m_score = safe_ntile(monetary),
      rfm_score = r_score + f_score + m_score,
      segment_rfm = case_when(
        r_score >= 4 & f_score >= 4 & m_score >= 4 ~ "Champions",
        r_score <= 2 & f_score >= 4 & m_score >= 4 ~ "Cannot Lose Them",
        f_score >= 4                               ~ "Loyal Customers",
        r_score >= 4 & f_score <= 2                ~ "New Customers",
        r_score >= 4                               ~ "Promising",
        r_score <= 2 & f_score >= 3                ~ "At Risk",
        r_score <= 2 & m_score >= 3                ~ "About to Sleep",
        r_score == 3                               ~ "Need Attention",
        TRUE                                       ~ "Hibernating"
      )
    )
}

# ------------------------------------------------------------------------------
# 4. Clustering engine
# ------------------------------------------------------------------------------
feature_matrix <- function(rfm, include_aov = FALSE) {
  df <- rfm %>%
    transmute(
      log_recency   = log1p(recency),
      log_frequency = log1p(frequency),
      log_monetary  = log1p(monetary)
    )
  if (include_aov) df$log_aov <- log1p(rfm$avg_order_value)
  scale(as.matrix(df))
}

run_kmeans <- function(mat, k, seed = 123) {
  set.seed(seed)
  kmeans(mat, centers = k, nstart = 25, iter.max = 200)
}

diagnose_k <- function(mat, max_k = 8, seed = 123) {
  d <- dist(mat)
  set.seed(seed)
  map_dfr(2:max_k, function(k) {
    km  <- kmeans(mat, centers = k, nstart = 20, iter.max = 200)
    sil <- silhouette(km$cluster, d)
    tibble(k = k,
           tot_withinss   = km$tot.withinss,
           avg_silhouette = mean(sil[, "sil_width"]))
  })
}

cluster_labels <- function(rfm, cluster) {
  medals <- c("Platinum", "Gold", "Silver", "Bronze")
  labs <- tibble(cluster = cluster, monetary = rfm$monetary) %>%
    group_by(cluster) %>%
    summarise(v = mean(monetary), .groups = "drop") %>%
    arrange(desc(v)) %>%
    mutate(label = if_else(row_number() <= length(medals),
                           medals[row_number()],
                           paste("Segment", row_number())))
  setNames(labs$label, labs$cluster)
}

# ------------------------------------------------------------------------------
# 5. UI
# ------------------------------------------------------------------------------
ui <- dashboardPage(
  skin = "blue",
  dashboardHeader(title = "Customer Segmentation Platform",
                  titleWidth = 320),
  dashboardSidebar(
    width = 260,
    sidebarMenu(
      id = "tabs",
      menuItem("Overview",          tabName = "overview",   icon = icon("dashboard")),
      menuItem("RFM Analysis",      tabName = "rfm",        icon = icon("table")),
      menuItem("ML Clustering",     tabName = "clustering", icon = icon("object-group")),
      menuItem("Segment Profiles",  tabName = "profiles",   icon = icon("users")),
      menuItem("Customer Explorer", tabName = "explorer",   icon = icon("search")),
      menuItem("Data",              tabName = "data",       icon = icon("database"))
    ),
    hr(),
    div(style = "padding: 0 15px;",
        radioButtons("seg_method", "Segmentation method",
                     choices = c("RFM rules" = "rfm",
                                 "K-Means (ML)" = "kmeans")))
  ),
  dashboardBody(
    tags$head(tags$style(HTML("
      .content-wrapper { background-color: #f4f6f9; }
      .box { border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,.10); }
      .small-box { border-radius: 8px; }
    "))),
    tabItems(
      # ---- Overview ---------------------------------------------------------
      tabItem("overview",
        fluidRow(
          valueBoxOutput("vb_customers", width = 3),
          valueBoxOutput("vb_revenue",   width = 3),
          valueBoxOutput("vb_aov",       width = 3),
          valueBoxOutput("vb_segments",  width = 3)
        ),
        fluidRow(
          box(width = 7, status = "primary", solidHeader = TRUE,
              title = "Customers by Segment",
              plotlyOutput("plt_seg_dist", height = 320)),
          box(width = 5, status = "primary", solidHeader = TRUE,
              title = "Revenue Share by Segment",
              plotlyOutput("plt_rev_share", height = 320))
        ),
        fluidRow(
          box(width = 12, status = "primary", solidHeader = TRUE,
              title = "Recency vs Frequency (bubble size = lifetime spend)",
              plotlyOutput("plt_rvf", height = 400))
        )
      ),
      # ---- RFM --------------------------------------------------------------
      tabItem("rfm",
        fluidRow(
          box(width = 6, status = "primary", solidHeader = TRUE,
              title = "RFM Heatmap (avg spend by R x F score)",
              plotlyOutput("plt_rfm_heat", height = 340)),
          box(width = 6, status = "primary", solidHeader = TRUE,
              title = "R / F / M Distributions",
              plotlyOutput("plt_rfm_dist", height = 340))
        ),
        fluidRow(
          box(width = 12, status = "info", solidHeader = TRUE,
              title = "RFM Segment Summary", DTOutput("tbl_rfm_summary"))
        )
      ),
      # ---- Clustering -------------------------------------------------------
      tabItem("clustering",
        fluidRow(
          box(width = 12, status = "warning", solidHeader = TRUE,
              title = "Cluster Settings",
              column(4, sliderInput("k", "Number of clusters (k)",
                                    min = 2, max = 10, value = 4)),
              column(4, numericInput("max_k", "Diagnostics max k",
                                     value = 8, min = 4, max = 12)),
              column(4, checkboxInput("use_aov",
                                      "Include avg order value feature", FALSE))
          )
        ),
        fluidRow(
          box(width = 6, status = "primary", solidHeader = TRUE,
              title = "Elbow Method", plotlyOutput("plt_elbow", height = 300)),
          box(width = 6, status = "primary", solidHeader = TRUE,
              title = "Silhouette Score", plotlyOutput("plt_silhouette", height = 300))
        ),
        fluidRow(
          box(width = 7, status = "primary", solidHeader = TRUE,
              title = "Cluster Map (PCA projection)",
              plotlyOutput("plt_pca", height = 380)),
          box(width = 5, status = "primary", solidHeader = TRUE,
              title = "Cluster Sizes", plotlyOutput("plt_cluster_size", height = 380))
        ),
        fluidRow(
          box(width = 12, status = "info", solidHeader = TRUE,
              title = "Feature Distributions by Cluster",
              plotlyOutput("plt_cluster_box", height = 320))
        )
      ),
      # ---- Profiles ---------------------------------------------------------
      tabItem("profiles",
        fluidRow(
          box(width = 7, status = "primary", solidHeader = TRUE,
              title = "Segment Radar (normalized scores)",
              plotlyOutput("plt_radar", height = 420)),
          box(width = 5, status = "success", solidHeader = TRUE,
              title = "Segment Playbook", DTOutput("tbl_playbook", height = 420))
        ),
        fluidRow(
          box(width = 12, status = "info", solidHeader = TRUE,
              title = "Segment Economics", DTOutput("tbl_seg_econ"))
        )
      ),
      # ---- Explorer ---------------------------------------------------------
      tabItem("explorer",
        fluidRow(
          box(width = 12, status = "primary", solidHeader = TRUE,
              title = "Customer-Level Segments",
              downloadButton("dl_customers", "Export CSV",
                             class = "btn-success"),
              br(), br(),
              DTOutput("tbl_customers"))
        )
      ),
      # ---- Data -------------------------------------------------------------
      tabItem("data",
        fluidRow(
          box(width = 5, status = "primary", solidHeader = TRUE,
              title = "Load Data",
              fileInput("file_upload", "Upload transactions CSV",
                        accept = c(".csv", "text/csv")),
              helpText("Required columns: customer_id, order_date, amount. ",
                       "Aliases (date, revenue, user_id, ...) auto-detected."),
              hr(),
              actionButton("btn_sample", "Load sample data",
                           icon = icon("database"), class = "btn-primary"),
              actionButton("btn_regen", "New random sample",
                           icon = icon("random")),
              hr(),
              verbatimTextOutput("txt_data_summary")),
          box(width = 7, status = "info", solidHeader = TRUE,
              title = "Data Preview", DTOutput("tbl_preview"))
        )
      )
    )
  )
)

# ------------------------------------------------------------------------------
# 6. Server
# ------------------------------------------------------------------------------
server <- function(input, output, session) {

  # ---- Reactive state --------------------------------------------------------
  transactions <- reactiveVal(generate_transactions())

  observeEvent(input$btn_sample, {
    transactions(generate_transactions())
    showNotification("Sample data loaded.", type = "message")
  })
  observeEvent(input$btn_regen, {
    transactions(generate_transactions(seed = sample.int(1e6, 1)))
    showNotification("New random sample generated.", type = "message")
  })
  observeEvent(input$file_upload, {
    ext <- tools::file_ext(input$file_upload$name)
    validate(need(tolower(ext) == "csv", "Please upload a .csv file."))

    raw <- tryCatch(
      read_csv(input$file_upload$datapath, show_col_types = FALSE),
      error = function(e) NULL
    )
    validate(need(!is.null(raw), "Could not parse the file."))

    df <- standardize_columns(raw)
    validate(need(all(c("customer_id", "order_date", "amount") %in% names(df)),
                  "CSV must contain: customer_id, order_date, amount"))

    tx <- df %>%
      transmute(
        customer_id = as.character(customer_id),
        order_date  = parse_order_date(order_date),
        amount      = parse_number(as.character(amount))
      ) %>%
      filter(!is.na(order_date), !is.na(amount), amount > 0)

    validate(need(nrow(tx) > 50, "Too few valid rows after cleaning (>50 needed)."))

    transactions(tx)
    showNotification(paste("Loaded", comma(nrow(tx)), "transactions."),
                     type = "message")
  })

  rfm_data <- reactive({
    req(transactions())
    compute_rfm(transactions())
  })

  cluster_model <- reactive({
    req(rfm_data(), input$k)
    mat  <- feature_matrix(rfm_data(), input$use_aov)
    km   <- run_kmeans(mat, input$k)
    pca  <- prcomp(mat)
    labs <- cluster_labels(rfm_data(), km$cluster)
    list(km = km, pca = pca,
         segment = unname(labs[as.character(km$cluster)]))
  })

  # Unified segmentation output used by all tabs
  model <- reactive({
    df <- rfm_data()
    if (input$seg_method == "kmeans") {
      cm <- cluster_model()
      df %>% mutate(segment = cm$segment, cluster = cm$km$cluster)
    } else {
      df %>% mutate(segment = segment_rfm, cluster = NA_integer_)
    }
  })

  diagnostics <- reactive({
    req(rfm_data())
    mat <- feature_matrix(rfm_data(), input$use_aov)
    diagnose_k(mat, max_k = input$max_k)
  }) %>% bindCache(input$use_aov, input$max_k, transactions())

  # ---- KPI value boxes -------------------------------------------------------
  output$vb_customers <- renderValueBox({
    valueBox(comma(nrow(model())), "Customers",
             icon = icon("users"), color = "blue")
  })
  output$vb_revenue <- renderValueBox({
    valueBox(dollar(sum(model()$monetary)), "Total Revenue",
             icon = icon("dollar-sign"), color = "green")
  })
  output$vb_aov <- renderValueBox({
    valueBox(dollar(mean(model()$avg_order_value)), "Avg Order Value",
             icon = icon("shopping-cart"), color = "purple")
  })
  output$vb_segments <- renderValueBox({
    valueBox(n_distinct(model()$segment), "Active Segments",
             icon = icon("object-group"), color = "yellow")
  })

  # ---- Overview plots --------------------------------------------------------
  output$plt_seg_dist <- renderPlotly({
    df <- model() %>% count(segment, name = "n") %>% mutate(pct = n / sum(n))
    p <- ggplot(df, aes(reorder(segment, n), n, fill = segment,
                        text = paste0(segment, "\n", comma(n), " customers (",
                                      percent(pct, 0.1), ")"))) +
      geom_col(show.legend = FALSE) + coord_flip() +
      scale_y_continuous(labels = comma) +
      labs(x = NULL, y = "Customers") + theme_minimal(base_size = 13)
    ggplotly(p, tooltip = "text")
  })

  output$plt_rev_share <- renderPlotly({
    df <- model() %>%
      group_by(segment) %>%
      summarise(revenue = sum(monetary), .groups = "drop")
    plot_ly(df, labels = ~segment, values = ~revenue, type = "pie", hole = 0.5,
            textinfo = "label+percent",
            hovertemplate = "%{label}<br>$%{value:,.0f}<br>%{percent}<extra></extra>",
            marker = list(line = list(color = "#ffffff", width = 1))) %>%
      layout(showlegend = FALSE, margin = list(t = 10, b = 10, l = 10, r = 10))
  })

  output$plt_rvf <- renderPlotly({
    df <- model()
    plot_ly(df, x = ~frequency, y = ~recency, color = ~segment,
            size = ~monetary, sizes = c(4, 30), opacity = 0.65,
            type = "scatter", mode = "markers",
            text = ~paste0(customer_id,
                           "<br>Orders: ", frequency,
                           "<br>Recency: ", recency, " days",
                           "<br>Spend: $", comma(monetary)),
            hoverinfo = "text",
            marker = list(sizemode = "diameter")) %>%
      layout(xaxis = list(title = "Frequency (orders)"),
             yaxis = list(title = "Recency (days since last order)"),
             legend = list(orientation = "h"))
  })

  # ---- RFM tab ---------------------------------------------------------------
  output$plt_rfm_heat <- renderPlotly({
    df <- rfm_data() %>%
      group_by(r_score, f_score) %>%
      summarise(avg_m = mean(monetary), n = n(), .groups = "drop")
    p <- ggplot(df, aes(f_score, r_score, fill = avg_m,
                        text = paste0("R:", r_score, "  F:", f_score,
                                      "\nCustomers: ", comma(n),
                                      "\nAvg spend: ", dollar(avg_m)))) +
      geom_tile(color = "white") +
      scale_fill_gradient(low = "#EDF4FB", high = "#2E86AB", labels = dollar) +
      scale_x_continuous(breaks = 1:5) + scale_y_continuous(breaks = 1:5) +
      labs(x = "Frequency score", y = "Recency score", fill = "Avg\nspend") +
      theme_minimal(base_size = 13)
    ggplotly(p, tooltip = "text")
  })

  output$plt_rfm_dist <- renderPlotly({
    df <- rfm_data() %>%
      select(recency, frequency, monetary) %>%
      pivot_longer(everything()) %>%
      mutate(name = recode(name, recency = "Recency (days)",
                           frequency = "Frequency (orders)",
                           monetary = "Monetary ($)"))
    p <- ggplot(df, aes(value, fill = name)) +
      geom_histogram(bins = 40, show.legend = FALSE, color = "white") +
      facet_wrap(~name, scales = "free") +
      scale_fill_manual(values = c("#2E86AB", "#18A558", "#F6AE2D")) +
      labs(x = NULL, y = "Customers") +
      theme_minimal(base_size = 12)
    ggplotly(p)
  })

  output$tbl_rfm_summary <- renderDT({
    rfm_data() %>%
      group_by(segment_rfm) %>%
      summarise(customers = n(),
                avg_recency   = mean(recency),
                avg_frequency = mean(frequency),
                avg_monetary  = mean(monetary),
                revenue       = sum(monetary),
                .groups = "drop") %>%
      arrange(desc(revenue)) %>%
      datatable(rownames = FALSE,
                options = list(dom = "t", pageLength = 12, scrollX = TRUE)) %>%
      formatRound(c("avg_recency", "avg_frequency"), 1) %>%
      formatCurrency(c("avg_monetary", "revenue"), "$", digits = 0)
  })

  # ---- Clustering tab --------------------------------------------------------
  output$plt_elbow <- renderPlotly({
    df <- diagnostics()
    p <- ggplot(df, aes(k, tot_withinss)) +
      geom_line(color = "#2E86AB", linewidth = 1) +
      geom_point(size = 3, color = "#2E86AB") +
      scale_x_continuous(breaks = df$k) +
      scale_y_continuous(labels = comma) +
      labs(x = "k", y = "Total within-cluster SS") +
      theme_minimal(base_size = 13)
    ggplotly(p)
  })

  output$plt_silhouette <- renderPlotly({
    df <- diagnostics()
    best <- df %>% slice_max(avg_silhouette, n = 1)
    p <- ggplot(df, aes(k, avg_silhouette)) +
      geom_line(color = "#18A558", linewidth = 1) +
      geom_point(size = 3, color = "#18A558") +
      geom_point(data = best, size = 5, color = "#D90368") +
      scale_x_continuous(breaks = df$k) +
      labs(x = "k", y = "Avg silhouette width (higher = better)",
           caption = paste0("Best k = ", best$k)) +
      theme_minimal(base_size = 13)
    ggplotly(p)
  })

  output$plt_pca <- renderPlotly({
    cm  <- cluster_model()
    ve  <- round(100 * summary(cm$pca)$importance[2, 1:2], 1)
    df  <- tibble(PC1 = cm$pca$x[, 1], PC2 = cm$pca$x[, 2],
                  segment = cm$segment, id = rfm_data()$customer_id)
    plot_ly(df, x = ~PC1, y = ~PC2, color = ~segment, text = ~id,
            type = "scatter", mode = "markers", opacity = 0.65,
            marker = list(size = 7)) %>%
      layout(xaxis = list(title = paste0("PC1 (", ve[1], "%)")),
             yaxis = list(title = paste0("PC2 (", ve[2], "%)")),
             legend = list(orientation = "h"))
  })

  output$plt_cluster_size <- renderPlotly({
    df <- model() %>% count(segment, name = "n") %>%
      mutate(pct = n / sum(n))
    plot_ly(df, x = ~n, y = ~reorder(segment, n), type = "bar",
            orientation = "h",
            text = ~paste0(comma(n), " (", percent(pct, 0.1), ")"),
            textposition = "auto",
            marker = list(color = "#2E86AB")) %>%
      layout(xaxis = list(title = "Customers"),
             yaxis = list(title = ""))
  })

  output$plt_cluster_box <- renderPlotly({
    df <- model() %>%
      select(segment, recency, frequency, monetary) %>%
      pivot_longer(-segment) %>%
      mutate(name  = factor(name, levels = c("recency", "frequency", "monetary")),
             value = if_else(name == "monetary", log10(value + 1), value))
    p <- ggplot(df, aes(segment, value, fill = segment)) +
      geom_boxplot(alpha = 0.7, outlier.alpha = 0.15, show.legend = FALSE) +
      facet_wrap(~name, scales = "free_y", nrow = 1,
                 labeller = as_labeller(c(recency = "Recency (days)",
                                          frequency = "Frequency (orders)",
                                          monetary = "log10 Monetary ($)"))) +
      labs(x = NULL, y = NULL) +
      theme_minimal(base_size = 12) +
      theme(axis.text.x = element_text(angle = 30, hjust = 1))
    ggplotly(p)
  })

  # ---- Profiles tab ----------------------------------------------------------
  output$plt_radar <- renderPlotly({
    norm <- function(x, invert = FALSE) {
      rng <- range(x)
      if (diff(rng) == 0) return(rep(50, length(x)))
      out <- 100 * (x - rng[1]) / diff(rng)
      if (invert) 100 - out else out
    }
    long <- model() %>%
      group_by(segment) %>%
      summarise(across(c(recency, frequency, monetary, avg_order_value), mean),
                .groups = "drop") %>%
      mutate(across(c(frequency, monetary, avg_order_value), norm),
             recency = norm(recency, invert = TRUE)) %>%
      rename(`Recency (score)` = recency, Frequency = frequency,
             Monetary = monetary, `Avg Order Value` = avg_order_value) %>%
      pivot_longer(-segment, names_to = "metric", values_to = "score")

    plot_ly(long, type = "scatterpolar", r = ~score, theta = ~metric,
            color = ~segment, fill = "toself", opacity = 0.6) %>%
      layout(polar = list(radialaxis = list(visible = TRUE, range = c(0, 100))),
             legend = list(orientation = "h"))
  })

  output$tbl_playbook <- renderDT({
    pb <- if (input$seg_method == "rfm") {
      tribble(
        ~segment,           ~priority,                 ~recommended_action,
        "Champions",        "Retain & upsell",         "Early access, loyalty rewards, referrals",
        "Loyal Customers",  "Grow",                    "Cross-sell, membership tiers",
        "New Customers",    "Onboard",                 "Welcome series, 2nd-purchase coupon",
        "Promising",        "Nurture",                 "Personalized recommendations",
        "Need Attention",   "Re-engage",               "Limited-time offers",
        "At Risk",          "Win back",                "Reactivation campaign + discount",
        "Cannot Lose Them", "Win back (high value)",   "1:1 outreach, premium offer",
        "About to Sleep",   "Reactivate",              "Email win-back series",
        "Hibernating",      "Low cost / sunset",       "Newsletter only, suppress paid ads"
      )
    } else {
      tribble(
        ~segment,   ~priority,         ~recommended_action,
        "Platinum", "Retain & grow",   "VIP program, concierge, early access",
        "Gold",     "Grow",            "Cross-sell, tier upgrade incentives",
        "Silver",   "Nurture",         "Personalized offers, frequency incentives",
        "Bronze",   "Activate",        "Onboarding, second-purchase campaign"
      )
    }
    datatable(pb, rownames = FALSE,
              options = list(dom = "t", pageLength = 12, scrollX = TRUE))
  })

  output$tbl_seg_econ <- renderDT({
    model() %>%
      group_by(segment) %>%
      summarise(customers     = n(),
                revenue       = sum(monetary),
                revenue_share = revenue / sum(model()$monetary),
                avg_recency   = mean(recency),
                avg_frequency = mean(frequency),
                avg_monetary  = mean(monetary),
                avg_annual_value = mean(annual_value),
                .groups = "drop") %>%
      arrange(desc(revenue)) %>%
      datatable(rownames = FALSE,
                options = list(dom = "t", pageLength = 12, scrollX = TRUE)) %>%
      formatCurrency(c("revenue", "avg_monetary", "avg_annual_value"), "$", digits = 0) %>%
      formatPercentage("revenue_share", 1) %>%
      formatRound(c("avg_recency", "avg_frequency"), 1)
  })

  # ---- Explorer tab ----------------------------------------------------------
  explorer_data <- reactive({
    model() %>%
      select(customer_id, segment, r_score, f_score, m_score, rfm_score,
             recency, frequency, monetary, avg_order_value, annual_value,
             first_purchase, last_purchase) %>%
      arrange(desc(monetary))
  })

  output$tbl_customers <- renderDT({
    datatable(explorer_data(), rownames = FALSE, filter = "top",
              extensions = "Buttons",
              options = list(dom = "Bfrtip", pageLength = 15, scrollX = TRUE,
                             buttons = c("copy", "csv", "excel"))) %>%
      formatCurrency(c("monetary", "avg_order_value", "annual_value"), "$", digits = 0) %>%
      formatRound("rfm_score", 0)
  })

  output$dl_customers <- downloadHandler(
    filename = function() paste0("customer_segments_", Sys.Date(), ".csv"),
    content  = function(file) write_csv(explorer_data(), file)
  )

  # ---- Data tab --------------------------------------------------------------
  output$txt_data_summary <- renderText({
    tx <- transactions()
    paste0(
      "Rows:        ", comma(nrow(tx)), "\n",
      "Customers:   ", comma(n_distinct(tx$customer_id)), "\n",
      "Date range:  ", min(tx$order_date), " -> ", max(tx$order_date), "\n",
      "Revenue:     ", dollar(sum(tx$amount))
    )
  })

  output$tbl_preview <- renderDT({
    datatable(head(transactions(), 500), rownames = FALSE,
              options = list(pageLength = 10, scrollX = TRUE))
  })
}

# ------------------------------------------------------------------------------
# 7. Launch (skipped when sourced by tests)
# ------------------------------------------------------------------------------
if (!isTRUE(getOption("csp.testmode"))) {
  shinyApp(ui, server)
}