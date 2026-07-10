# Basic CRUD example for the MongrelDB R client.
#
# Connects to a running mongreldb-server, creates a table, inserts rows,
# queries them back, and prints the count.
#
#   Rscript -e 'library(MongrelDB); source("examples/basic_crud.R")'

library(MongrelDB)

url <- Sys.getenv("MONGRELDB_URL", "http://127.0.0.1:8453")
db <- mongreldb_connect(url)

cat("health:", mongreldb_health(db), "\n")

# Per-run unique suffix so concurrent/CI runs never collide on a table name.
table <- sprintf("r_orders_example_%d", as.integer(Sys.time()))

# Guaranteed cleanup: ALWAYS drop the table at exit, even if the body errors,
# so CI runs never leave an orphan table behind.
on.exit(try(mongreldb_drop_table(db, table), silent = TRUE))

# The daemon requires JSON booleans for primary_key / nullable.
columns <- list(
  list(id = 1, name = "id",       ty = "int64",   primary_key = TRUE,  nullable = FALSE),
  list(id = 2, name = "customer", ty = "varchar", primary_key = FALSE, nullable = FALSE),
  list(id = 3, name = "amount",   ty = "float64", primary_key = FALSE, nullable = FALSE)
)

mongreldb_create_table(db, table, columns)

# Columns can also carry enum_variants (allowed values for a varchar column)
# and default_value (used when a put omits the cell). Both keys pass through
# to the server verbatim.
tasks <- sprintf("r_tasks_example_%d", as.integer(Sys.time()))
on.exit(try(mongreldb_drop_table(db, tasks), silent = TRUE))

task_columns <- list(
  list(id = 1, name = "id",    ty = "int64",   primary_key = TRUE,  nullable = FALSE),
  list(id = 2, name = "title", ty = "varchar", primary_key = FALSE, nullable = FALSE),
  list(
    id = 3, name = "status", ty = "varchar",
    primary_key   = FALSE, nullable = FALSE,
    enum_variants = list("todo", "doing", "done"),
    default_value  = "todo"
  )
)
mongreldb_create_table(db, tasks, task_columns)
# Omitting cell `3` falls back to default_value = "todo" on the server.
mongreldb_put(db, tasks, list(`1` = 1, `2` = "wire up the schema"))
mongreldb_put(db, tasks, list(`1` = 2, `2` = "ship the docs", `3` = "done"))

# Cells map column id to value.
mongreldb_put(db, table, list(`1` = 1, `2` = "Alice", `3` = 99.50))
mongreldb_put(db, table, list(`1` = 2, `2` = "Bob",   `3` = 150.00))

# Upsert updates on PK conflict.
mongreldb_upsert(db, table, list(`1` = 1, `2` = "Alice", `3` = 120.00),
  list(`3` = 120.00))

cat("count:", mongreldb_count(db, table), "\n")

# Query with a native index condition (primary key match).
res <- mongreldb_query(db, table, list(mongreldb_condition("pk", list(value = 1))))
for (row in res$rows) {
  cat("row:", paste(unlist(row$cells), collapse = ", "), "\n")
}

# Run SQL.
mongreldb_sql(db, sprintf("UPDATE %s SET amount = 200.0 WHERE customer = 'Bob'", table))
cat("count after sql:", mongreldb_count(db, table), "\n")
