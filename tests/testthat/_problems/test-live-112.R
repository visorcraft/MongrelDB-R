# Extracted from test-live.R:112

# setup ------------------------------------------------------------------------
library(testthat)
test_env <- simulate_test_env(package = "MongrelDB", path = "..")
attach(test_env, warn.conflicts = FALSE)

# prequel ----------------------------------------------------------------------
server_url <- Sys.getenv("MONGRELDB_URL", "http://127.0.0.1:8453")
probe <- tryCatch({
  db <- mongreldb_connect(server_url)
  mongreldb_health(db)
}, error = function(e) FALSE)
skip_if_not(isTRUE(probe),
  message = paste0("MONGRELDB_URL not reachable at ", server_url))
columns <- list(
  list(id = 1, name = "id",     ty = "int64",   primary_key = TRUE,  nullable = FALSE),
  list(id = 2, name = "label",  ty = "varchar", primary_key = FALSE, nullable = FALSE),
  list(id = 3, name = "amount", ty = "float64", primary_key = FALSE, nullable = FALSE)
)
unique_suffix <- as.character(as.integer(Sys.time()))

# test -------------------------------------------------------------------------
db <- mongreldb_connect(server_url)
table <- paste0("r_schema_", unique_suffix)
mongreldb_create_table(db, table, columns)
names <- mongreldb_tables(db)
expect_true(table %in% names)
