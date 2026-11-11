make_tx <- function() {
  tibble(
    customer_id = c("A", "A", "A", "B", "B", "C"),
    order_date  = as.Date(c("2024-01-01", "2024-03-01", "2024-06-01",
                            "2024-05-01", "2024-06-05", "2023-12-01")),
    amount      = c(100, 150, 200, 50, 75, 300)
  )
}

test_that("compute_rfm returns one row per customer with expected columns", {
  rfm <- compute_rfm(make_tx(), analysis_date = as.Date("2024-06-10"))
  expect_equal(nrow(rfm), 3)
  expect_true(all(c("recency", "frequency", "monetary",
                    "r_score", "f_score", "m_score",
                    "rfm_score", "segment_rfm") %in% names(rfm)))
})

test_that("recency equals days between analysis date and last purchase", {
  rfm <- compute_rfm(make_tx(), analysis_date = as.Date("2024-06-10"))
  expect_equal(rfm$recency[rfm$customer_id == "A"], 9)   # 2024-06-01 -> 9 days
  expect_equal(rfm$recency[rfm$customer_id == "B"], 5)   # 2024-06-05 -> 5 days
})

test_that("monetary aggregates correctly", {
  rfm <- compute_rfm(make_tx(), analysis_date = as.Date("2024-06-10"))
  expect_equal(rfm$monetary[rfm$customer_id == "A"], 450)
  expect_equal(rfm$frequency[rfm$customer_id == "B"], 2)
})

test_that("scores stay within bounds", {
  rfm <- compute_rfm(generate_transactions(n_customers = 200))
  expect_true(all(between(rfm$r_score, 1, 5)))
  expect_true(all(between(rfm$f_score, 1, 5)))
  expect_true(all(between(rfm$m_score, 1, 5)))
  expect_true(all(between(rfm$rfm_score, 3, 15)))
})

test_that("segment labels are from the known set", {
  rfm <- compute_rfm(generate_transactions(n_customers = 200))
  known <- c("Champions", "Cannot Lose Them", "Loyal Customers",
             "New Customers", "Promising", "At Risk",
             "About to Sleep", "Need Attention", "Hibernating")
  expect_true(all(rfm$segment_rfm %in% known))
})

test_that("single-purchase customers do not error", {
  tx <- tibble(customer_id = "A", order_date = as.Date("2024-01-01"), amount = 10)
  rfm <- compute_rfm(tx, analysis_date = as.Date("2024-06-01"))
  expect_equal(nrow(rfm), 1)
  expect_equal(rfm$frequency, 1)
})