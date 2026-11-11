rfm_small <- compute_rfm(generate_transactions(n_customers = 120))

test_that("run_kmeans partitions all customers", {
  mat <- feature_matrix(rfm_small)
  km  <- run_kmeans(mat, k = 3)
  expect_equal(length(km$cluster), 120)
  expect_equal(sort(unique(km$cluster)), 1:3)
  expect_equal(sum(km$size), 120)
})

test_that("run_kmeans is reproducible with fixed seed", {
  mat <- feature_matrix(rfm_small)
  km1 <- run_kmeans(mat, 3, seed = 7)
  km2 <- run_kmeans(mat, 3, seed = 7)
  expect_identical(km1$cluster, km2$cluster)
})

test_that("diagnose_k returns metrics for k = 2..max_k", {
  mat <- feature_matrix(rfm_small)
  d   <- diagnose_k(mat, max_k = 5)
  expect_equal(d$k, 2:5)
  expect_true(all(d$avg_silhouette >= -1 & d$avg_silhouette <= 1))
  expect_true(all(d$tot_withinss > 0))
})

test_that("cluster_labels ranks highest-spend cluster as Platinum", {
  rfm <- tibble(customer_id = letters[1:4],
                monetary    = c(1000, 10, 500, 100))
  labs <- cluster_labels(rfm, cluster = c(1, 2, 3, 4))
  expect_equal(unname(labs["1"]), "Platinum")
  expect_equal(unname(labs["3"]), "Gold")
  expect_equal(unname(labs["2"]), "Bronze")
})