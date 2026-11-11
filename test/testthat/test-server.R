test_that("server computes segmentation for both methods", {
  testServer(server, {
    # shrink dataset for speed
    transactions(generate_transactions(n_customers = 150))

    session$setInputs(seg_method = "rfm", k = 4,
                      use_aov = FALSE, max_k = 8)

    m1 <- model()
    expect_s3_class(m1, "data.frame")
    expect_equal(nrow(m1), 150)
    expect_true("segment" %in% names(m1))

    session$setInputs(seg_method = "kmeans")
    m2 <- model()
    expect_true(all(m2$segment %in% c("Platinum", "Gold", "Silver", "Bronze")))
    expect_true(all(!is.na(m2$cluster)))
  })
})

test_that("explorer_data is sorted by monetary descending", {
  testServer(server, {
    transactions(generate_transactions(n_customers = 150))
    session$setInputs(seg_method = "rfm", k = 4, use_aov = FALSE)
    df <- explorer_data()
    expect_true(all(diff(df$monetary) <= 0))
  })
})