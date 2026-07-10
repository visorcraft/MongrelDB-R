# Extracted from test-json.R:26

# setup ------------------------------------------------------------------------
library(testthat)
test_env <- simulate_test_env(package = "MongrelDB", path = "..")
attach(test_env, warn.conflicts = FALSE)

# test -------------------------------------------------------------------------
flap <- "mångrel"
expect_equal(
    jsonlite::fromJSON(jsonlite::toJSON(flap), simplifyVector = FALSE),
    flap
  )
