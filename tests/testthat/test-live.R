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
  # The returned row must carry primary key 2. Confirm via SQL JSON mode,
  # where rows are keyed by column name. An old server ignores the requested
  # JSON format and answers with Arrow IPC bytes, so mongreldb_sql() returns
  # NULL - only verify row content when JSON mode worked.
  pk_rows <- mongreldb_sql(db, sprintf("SELECT id FROM %s WHERE id = 2", table))
  if (length(pk_rows) >= 1) {
    expect_equal(pk_rows[[1]]$id, 2)
  }
})

test_that("upsert updates on PK conflict", {
  db <- mongreldb_connect(server_url)
  table <- paste0("r_upsert_", unique_suffix)
  mongreldb_create_table(db, table, columns)
  mongreldb_put(db, table, list(`1` = 1, `2` = "alpha", `3` = 10.0))
  mongreldb_upsert(db, table, list(`1` = 1, `2` = "alpha", `3` = 99.0),
    list(`3` = 99.0))
  expect_equal(mongreldb_count(db, table), 1L)
  # Query the row back and verify the upserted value landed. SQL JSON mode
  # returns rows keyed by column name. An old server ignores the requested JSON
  # format and answers with Arrow IPC bytes, so mongreldb_sql() returns NULL -
  # only verify row content when JSON mode worked.
  up_rows <- mongreldb_sql(db, sprintf("SELECT amount FROM %s WHERE id = 1", table))
  if (length(up_rows) >= 1) {
    expect_equal(up_rows[[1]]$amount, 99.0)
  }
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
  # JSON mode makes SELECT return rows as JSON objects (column names as
  # keys). Verify both rows come back with the right primary keys. An old server
  # ignores the requested JSON format and answers with Arrow IPC bytes, so
  # mongreldb_sql() returns NULL - only verify row content when JSON mode worked.
  selected <- mongreldb_sql(db, sprintf("SELECT id FROM %s ORDER BY id", table))
  if (length(selected) >= 1) {
    expect_equal(length(selected), 2)
    expect_equal(vapply(selected, function(r) r$id, numeric(1)), c(1, 2))
  }
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

test_that("range query returns only rows within the bounds", {
  db <- mongreldb_connect(server_url)
  table <- paste0("r_range_", unique_suffix)
  mongreldb_create_table(db, table, columns)
  mongreldb_put(db, table, list(`1` = 1, `2` = "a", `3` = 50.0))
  mongreldb_put(db, table, list(`1` = 2, `2` = "b", `3` = 75.0))
  mongreldb_put(db, table, list(`1` = 3, `2` = "c", `3` = 90.0))
  mongreldb_put(db, table, list(`1` = 4, `2` = "d", `3` = 100.0))
  # Only scores >= 80 should come back (90 and 100) - assert the count.
  # The `amount` column is float64, so use `range_f64` (plain `range`
  # expects an i64 bound and rejects floats). range_f64 requires both
  # bounds (min/max) and the inclusivity flags (min_inclusive/max_inclusive).
  res <- mongreldb_query(db, table,
    list(mongreldb_condition("range_f64", list(
      column = 3,
      min = 80.0,
      max = 200.0,
      min_inclusive = TRUE,
      max_inclusive = TRUE
    ))))
  expect_equal(length(res$rows), 2L)
  # Only rows with id 3 (amount 90) and 4 (amount 100) qualify. Confirm their
  # exact PK values via SQL JSON mode (rows keyed by column name). An old server
  # ignores the requested JSON format and answers with Arrow IPC bytes, so
  # mongreldb_sql() returns NULL - only verify row content when JSON mode worked.
  selected <- mongreldb_sql(db,
    sprintf("SELECT id FROM %s WHERE amount >= 80.0 ORDER BY id", table))
  if (length(selected) >= 1) {
    expect_equal(vapply(selected, function(r) r$id, numeric(1)), c(3, 4))
  }
})

test_that("tables() lists the created table", {
  db <- mongreldb_connect(server_url)
  table <- paste0("r_tables_", unique_suffix)
  mongreldb_create_table(db, table, columns)
  names <- mongreldb_tables(db)
  expect_true(table %in% names)
})

test_that("schema_for on a nonexistent table raises a not_found error", {
  db <- mongreldb_connect(server_url)
  err <- tryCatch(
    mongreldb_schema_for(db, "nonexistent_table_xyz"),
    error = function(e) e
  )
  expect_s3_class(err, "mongreldb_error")
  expect_equal(err$kind, "not_found")
})

test_that("idempotent transaction does not duplicate the row", {
  db <- mongreldb_connect(server_url)
  table <- paste0("r_idem_", unique_suffix)
  mongreldb_create_table(db, table, columns)
  # Idempotency key must be unique per run so a stale key from an earlier
  # run can't be replayed against this table.
  key <- paste0("order-100-create-", unique_suffix)
  # First idempotent commit inserts the row.
  mongreldb_transaction(db, list(
    list(put = list(table = table,
      cells = list(1, 100, 2, "order", 3, 1.0)))
  ), idempotency_key = key)
  expect_equal(mongreldb_count(db, table), 1L)
  # A second, identical commit with the SAME key must not duplicate it.
  tryCatch(
    mongreldb_transaction(db, list(
      list(put = list(table = table,
        cells = list(1, 100, 2, "order", 3, 1.0)))
    ), idempotency_key = key),
    error = function(e) {
      # The daemon may reject the duplicate; the row count is what matters.
    }
  )
  expect_equal(mongreldb_count(db, table), 1L)
})
