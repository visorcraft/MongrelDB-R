# Quickstart

This guide walks through installing the MongrelDB R client, connecting to a
running `mongreldb-server`, and doing your first round-trip of CRUD and query.

## Prerequisites

- R 4.0 or newer.
- The `curl` and `jsonlite` CRAN packages (`install.packages(c("curl", "jsonlite"))`).
- A running [`mongreldb-server`](https://github.com/visorcraft/MongrelDB)
  daemon. The simplest start is the prebuilt Linux binary:

  ```sh
  curl -L -o mongreldb-server \
    https://github.com/visorcraft/MongrelDB/releases/download/v0.58.3/mongreldb-server-linux-x64
  chmod +x mongreldb-server
  ./mongreldb-server ./data --port 8453
  ```

## Install

Install from source:

```sh
R CMD INSTALL .
```

or from within R:

```r
install.packages(".", repos = NULL, type = "source")
```

The client depends on `curl` and `jsonlite` only.

## Connect

```r
library(MongrelDB)

db <- mongreldb_connect("http://127.0.0.1:8453")
print(mongreldb_health(db))   # TRUE
```

## Create a table and insert rows

```r
# The daemon requires JSON booleans for primary_key / nullable.
columns <- list(
  list(id = 1, name = "id",       ty = "int64",   primary_key = TRUE,  nullable = FALSE),
  list(id = 2, name = "customer", ty = "varchar", primary_key = FALSE, nullable = FALSE),
  list(id = 3, name = "amount",   ty = "float64", primary_key = FALSE, nullable = FALSE)
)
mongreldb_create_table(db, "orders", columns)

# Column descriptors can also carry enum_variants (allowed values for a
# varchar column) and default_value (used when a put omits the cell). Both
# keys pass through to the server verbatim.
task_columns <- list(
  list(id = 1, name = "id",     ty = "int64",   primary_key = TRUE,  nullable = FALSE),
  list(id = 2, name = "title",  ty = "varchar", primary_key = FALSE, nullable = FALSE),
  list(
    id = 3, name = "status", ty = "varchar",
    primary_key   = FALSE, nullable = FALSE,
    enum_variants = list("todo", "doing", "done"),
    default_value  = "todo"
  )
)
mongreldb_create_table(db, "tasks", task_columns)

# default_value accepts any JSON scalar; supply the column's expected type.
# An explicit NULL stays a static null, a missing default_value means no
# default, and literal "now"/"uuid" values in default_value are static strings.
# Use default_expr = "now" or "uuid" for a dynamic default.

event_columns <- list(
  list(id = 1, name = "message", ty = "varchar",   primary_key = FALSE, nullable = FALSE, default_value = "none"),
  list(id = 2, name = "count",   ty = "int64",     primary_key = FALSE, nullable = FALSE, default_value = 0),
  list(id = 3, name = "active",  ty = "bool",      primary_key = FALSE, nullable = FALSE, default_value = TRUE),
  list(id = 4, name = "extra",   ty = "varchar",   primary_key = FALSE, nullable = TRUE,  default_value = NULL),
  list(id = 5, name = "tag",     ty = "varchar",   primary_key = FALSE, nullable = FALSE, default_value = "now"),
  list(id = 6, name = "created", ty = "timestamp", primary_key = FALSE, nullable = FALSE, default_expr = "now")
)
mongreldb_create_table(db, "events", event_columns)

# Cells map column id to value.
mongreldb_put(db, "orders", list(`1` = 1, `2` = "Alice", `3` = 99.50))
mongreldb_put(db, "orders", list(`1` = 2, `2` = "Bob",   `3` = 150.00))

print(mongreldb_count(db, "orders"))   # 2
```

## Run a query

```r
res <- mongreldb_query(db, "orders",
  list(mongreldb_condition("pk", list(value = 1))))
```

## History retention

Control the time-travel window and query historical rows with `AS OF EPOCH`:

```r
window  <- mongreldb_history_retention_epochs(db)
earliest <- mongreldb_earliest_retained_epoch(db)

# Requires admin auth. Increasing the window cannot restore already-pruned
# history past the previous earliest epoch.
mongreldb_set_history_retention_epochs(db, window + 10)

rows <- mongreldb_sql(db, sprintf("SELECT id FROM orders AS OF EPOCH %s", earliest))
```

## Next steps

- [Transactions](transactions.md) for atomic multi-op commits.
- [Queries](queries.md) for the native index condition API.
- [SQL](sql.md) for DataFusion-backed ad-hoc SQL.
- [Auth](auth.md) for Bearer and Basic authentication.
- [Errors](errors.md) for the exception hierarchy.
