# Extracted from test-json.R:94

# setup ------------------------------------------------------------------------
library(testthat)
test_env <- simulate_test_env(package = "MongrelDB", path = "..")
attach(test_env, warn.conflicts = FALSE)

# test -------------------------------------------------------------------------
expect_error(MongrelDB:::reject_nonfinite(list(Inf)), "NA|NaN|Infinity")
expect_error(MongrelDB:::reject_nonfinite(list(NaN)), "NA|NaN|Infinity")
expect_error(MongrelDB:::reject_nonfinite(list(NA)), "NA|NaN|Infinity")
