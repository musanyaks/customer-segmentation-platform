test_that("feature_matrix returns standardized 3-column matrix", {
  rfm <- compute_rfm(generate_transactions(n_customers = 100))
  mat <- feature_matrix(rfm)
  expect_true(is.matrix(mat))
  expect_equal(nrow(mat), 100)
  expect_equal(colnames(mat), c("log_recency", "log_frequency", "log_monetary"))
  expect_equal(colMeans(mat), c(0, 0, 0), tolerance = 1e-8)
})

test_that("include_aov adds a fourth column", {
  rfm <- compute_rfm(generate_transactions(n_customers = 100))
  mat <- feature_matrix(rfm, include_aov = TRUE)
  expect_equal(ncol(mat), 4)
  expect_true("log_aov" %in% colnames(mat))
})