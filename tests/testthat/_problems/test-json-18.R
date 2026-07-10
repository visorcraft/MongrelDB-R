# Extracted from test-json.R:18

# setup ------------------------------------------------------------------------
library(testthat)
test_env <- simulate_test_env(package = "MongrelDB", path = "..")
attach(test_env, warn.conflicts = FALSE)

# test -------------------------------------------------------------------------
expect_equal(jsonlite::fromJSON(jsonlite::toJSON(1:3)), 1:3)
obj <- list(a = 1, b = 2)
expect_equal(jsonlite::fromJSON(jsonlite::toJSON(obj), simplifyVector = FALSE), obj)
