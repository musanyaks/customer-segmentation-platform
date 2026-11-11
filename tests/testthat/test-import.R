test_that("standardize_columns maps common aliases", {
  df <- tibble(User_ID = 1, InvoiceDate = "2024-01-01", Revenue = 10)
  out <- standardize_columns(df)
  expect_true(all(c("customer_id", "order_date", "amount") %in% names(out)))
})

test_that("standardize_columns leaves canonical names untouched", {
  df <- tibble(customer_id = 1, order_date = "2024-01-01", amount = 10)
  out <- standardize_columns(df)
  expect_equal(names(out), c("customer_id", "order_date", "amount"))
})

test_that("parse_order_date handles common formats", {
  expect_equal(parse_order_date("2024-01-15"),      as.Date("2024-01-15"))
  expect_equal(parse_order_date("15/01/2024"),      as.Date("2024-01-15"))
  expect_equal(parse_order_date("01/15/2024"),      as.Date("2024-01-15"))
  expect_equal(parse_order_date(as.Date("2024-01-15")), as.Date("2024-01-15"))
})

test_that("parse_order_date handles Excel serials", {
  expect_equal(parse_order_date(45000),
               as.Date(45000, origin = "1899-12-30"))
})