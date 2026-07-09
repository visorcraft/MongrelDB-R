# Live integration tests for the MongrelDB R client.
#
# These tests round-trip data through every public method against a real
# mongreldb-server. They skip automatically when no daemon is reachable at the
# URL in MONGRELDB_URL (default http://127.0.0.1:8453), so the suite still
# passes offline.

server_url <- Sys.getenv("MONGRELDB_URL", "http://127.0.0.1:8453")

# Probe the daemon once. If it is not up, skip every live test.
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

test_that("health returns true", {
  db <- mongreldb_connect(server_url)
  expect_true(mongreldb_health(db))
})

test_that("createTable, put, count, query round-trip", {
  db <- mongreldb_connect(server_url)
  table <- paste0("r_items_", unique_suffix)
  mongreldb_create_table(db, table, columns)
  mongreldb_put(db, table, list(`1` = 1, `2` = "alpha", `3` = 10.0))
  mongreldb_put(db, table, list(`1` = 2, `2` = "beta",  `3` = 25.0))
  expect_equal(mongreldb_count(db, table), 2L)
  res <- mongreldb_query(db, table,
    list(mongreldb_condition("pk", list(value = 2))))
  expect_gte(length(res$rows), 1)
})

test_that("upsert updates on PK conflict", {
  db <- mongreldb_connect(server_url)
  table <- paste0("r_upsert_", unique_suffix)
  mongreldb_create_table(db, table, columns)
  mongreldb_put(db, table, list(`1` = 1, `2` = "alpha", `3` = 10.0))
  mongreldb_upsert(db, table, list(`1` = 1, `2` = "alpha", `3` = 99.0),
    list(`3` = 99.0))
  expect_equal(mongreldb_count(db, table), 1L)
})

test_that("transaction commits multiple ops atomically", {
  db <- mongreldb_connect(server_url)
  table <- paste0("r_txn_", unique_suffix)
  mongreldb_create_table(db, table, columns)
  mongreldb_transaction(db, list(
    list(put = list(table = table,
      cells = list(1, 10, 2, "dave", 3, 50.0))),
    list(put = list(table = table,
      cells = list(1, 11, 2, "eve", 3, 75.0)))
  ))
  expect_equal(mongreldb_count(db, table), 2L)
  # delete_by_pk in a follow-up txn removes the row.
  mongreldb_transaction(db, list(
    list(delete_by_pk = list(table = table, pk = 10))
  ))
  expect_equal(mongreldb_count(db, table), 1L)
})

test_that("sql round-trips", {
  db <- mongreldb_connect(server_url)
  table <- paste0("r_sql_", unique_suffix)
  mongreldb_create_table(db, table, columns)
  mongreldb_put(db, table, list(`1` = 1, `2` = "alpha", `3` = 1.0))
  mongreldb_sql(db, sprintf(
    "INSERT INTO %s (id, label, amount) VALUES (2, 'beta', 2.0)", table))
  expect_equal(mongreldb_count(db, table), 2L)
})

test_that("schema lists the created table", {
  db <- mongreldb_connect(server_url)
  table <- paste0("r_schema_", unique_suffix)
  mongreldb_create_table(db, table, columns)
  names <- mongreldb_tables(db)
  expect_true(table %in% names)
  desc <- mongreldb_schema_for(db, table)
  expect_gt(length(desc), 0)
})
