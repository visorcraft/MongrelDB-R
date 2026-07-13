<p align="center">
  <img src="assets/mongrel.png" alt="MongrelDB logo" width="250" />
</p>

<h1 align="center">MongrelDB R Client</h1>

<p align="center">
  <b>Pure R client for MongrelDB, embedded and server database with SQL, vector search, full-text search, and AI-native retrieval.</b>
</p>

<p align="center">
  <a href="https://cran.r-project.org/package=MongrelDB"><img src="https://img.shields.io/badge/CRAN-MongrelDB-276DC3.svg" alt="CRAN" /></a>
  <a href="https://www.r-project.org/"><img src="https://img.shields.io/badge/R-%3E%3D4.0-276DC3.svg" alt="R" /></a>
  <a href="#license"><img src="https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue.svg" alt="License" /></a>
</p>

## Package

| Surface | Package | Install |
|---|---|---|
| R client | `MongrelDB` | `install.packages("MongrelDB")` or `R CMD INSTALL .` |

## Requirements

- **R 4.0 or newer** (R 4.4 supported)
- The **curl** and **jsonlite** CRAN packages
- A running [`mongreldb-server`](https://github.com/visorcraft/MongrelDB) daemon

## What It Provides

- **Typed CRUD** over the Kit transaction endpoint: `put`, `upsert` (insert-or-update on PK conflict), `delete` by row id or primary key, with idempotency keys for safe retries.
- **Native query conditions** that push down to the engine's specialized indexes for sub-millisecond lookups: bitmap equality/IN, learned-range, null checks, FM-index full-text search, HNSW vector similarity (`ann`), and sparse vector match.
- **Idempotent batch transactions**, all operations staged in a list and committed atomically, with the engine enforcing unique, foreign key, and check constraints at commit time. Idempotency keys return the original response on duplicate commits, even after a crash.
- **Full SQL access** through the DataFusion-backed `/sql` endpoint: recursive CTEs, window functions, `CREATE TABLE AS SELECT`, materialized views, multi-statement execution, and the `mongreldb_fts_rank` relevance-scoring UDF.
- **Schema management**: typed table creation, full schema catalog, and per-table descriptors.
- **curl transport** with connection pooling via the `curl` package, a standard CRAN dependency.
- **Typed condition objects** (`mongreldb_error`) with a `$kind` field: `auth` (401/403), `not_found` (404), `constraint` (409, with error code and op index), `connection` (network), and `query` (everything else).
- **Robust JSON handling**: `NA`, NaN, and Infinity raise a clear error instead of corrupting data; malformed UTF-8 is passed through so the daemon can substitute it.

## Examples

Runnable, commented examples live in [`examples/`](examples):

- [Basic CRUD](examples/basic_crud.R), connect, create a table, insert, query, count.

## Quick Example

```r
library(MongrelDB)

# Connect to a running mongreldb-server daemon.
db <- mongreldb_connect("http://127.0.0.1:8453")

# The daemon requires JSON booleans for primary_key / nullable.
columns <- list(
  list(id = 1, name = "id",       ty = "int64",   primary_key = TRUE,  nullable = FALSE),
  list(id = 2, name = "customer", ty = "varchar", primary_key = FALSE, nullable = FALSE),
  list(id = 3, name = "amount",   ty = "float64", primary_key = FALSE, nullable = FALSE)
)

# Create a table.
mongreldb_create_table(db, "orders", columns)

# Column descriptors can also carry enum_variants (allowed values for an
# enum column), default_value (any correctly typed JSON scalar), and
# default_expr ("now" or "uuid"). These keys pass through to the server
# verbatim. An explicit NULL default_value stays a static null, a missing
# default_value means no default, and literal "now"/"uuid" values in
# default_value are static strings.
task_columns <- list(
  list(id = 1, name = "id",     ty = "int64",   primary_key = TRUE,  nullable = FALSE),
  list(id = 2, name = "title",  ty = "varchar", primary_key = FALSE, nullable = FALSE),
  list(
    id = 3, name = "status", ty = "enum",
    primary_key  = FALSE, nullable = FALSE,
    enum_variants = list("todo", "doing", "done"),
    default_value  = "todo"
  )
)
checks <- list(checks = list(list(
  id = 1,
  name = "ck_status",
  expr = list(IsNotNull = 3)
)))
mongreldb_create_table(db, "tasks", task_columns, constraints = checks)

# All static-default shapes pass through with their original JSON types.
event_columns <- list(
  list(id = 1, name = "message", ty = "varchar",   primary_key = FALSE, nullable = FALSE, default_value = "none"),
  list(id = 2, name = "count",   ty = "int64",     primary_key = FALSE, nullable = FALSE, default_value = 0),
  list(id = 3, name = "active",  ty = "bool",      primary_key = FALSE, nullable = FALSE, default_value = TRUE),
  list(id = 4, name = "extra",   ty = "varchar",   primary_key = FALSE, nullable = TRUE,  default_value = NULL),
  list(id = 5, name = "tag",     ty = "varchar",   primary_key = FALSE, nullable = FALSE, default_value = "now"),
  list(id = 6, name = "created", ty = "timestamp", primary_key = FALSE, nullable = FALSE, default_expr = "now")
)
mongreldb_create_table(db, "events", event_columns)

# Insert rows. Cells map column id to value.
mongreldb_put(db, "orders", list(`1` = 1, `2` = "Alice", `3` = 99.50))
mongreldb_put(db, "orders", list(`1` = 2, `2` = "Bob",   `3` = 150.00))

# Upsert (insert or update on PK conflict).
mongreldb_upsert(db, "orders", list(`1` = 1, `2` = "Alice", `3` = 120.00),
  list(`3` = 120.00))

# Query with a native index condition (learned-range index).
res <- mongreldb_query(db, "orders", list(
  mongreldb_condition("range_f64", list(column = 3, min = 100.0))
), projection = c(1, 2), limit = 100)

print(mongreldb_count(db, "orders"))   # 2

# Run SQL.
mongreldb_sql(db, "UPDATE orders SET amount = 200.0 WHERE customer = 'Bob'")
```

## Auth

```r
# Bearer token (--auth-token mode).
db <- mongreldb_connect("http://127.0.0.1:8453", token = "my-secret-token")

# HTTP Basic (--auth-users mode).
db <- mongreldb_connect("http://127.0.0.1:8453",
  username = "admin", password = "s3cret")
```

## Transactions

Operations are staged in a list and committed atomically. The engine enforces
unique, foreign key, and check constraints at commit time.

```r
ops <- list(
  list(put          = list(table = "orders", cells = list(1, 10, 2, "Dave", 3, 50.0))),
  list(put          = list(table = "orders", cells = list(1, 11, 2, "Eve",  3, 75.0))),
  list(delete_by_pk = list(table = "orders", pk = 2))
)

tryCatch(
  mongreldb_transaction(db, ops),    # atomic, all or nothing
  mongreldb_error = function(e) {
    if (e$kind == "constraint") {
      message("Constraint violated: ", e$error_code, " - ", e$message)
    }
  }
)

# Idempotent commit, safe to retry; daemon returns the original response.
mongreldb_transaction(db, ops2, "order-20-create")
```

## Query builder

Conditions push down to the engine's specialized indexes. `mongreldb_condition`
accepts friendly aliases that are translated to the server's on-wire keys:
`column` (to `column_id`), `min`/`max` (to `lo`/`hi`). The canonical keys are
also accepted directly.

```r
# Bitmap equality (low-cardinality columns).
mongreldb_query(db, "orders", list(
  mongreldb_condition("bitmap_eq", list(column = 2, value = "Alice"))))

# Range query (learned-range index).
mongreldb_query(db, "orders", list(
  mongreldb_condition("range_f64", list(column = 3, min = 50.0, max = 150.0))
), limit = 100)

# Full-text search (FM-index).
mongreldb_query(db, "documents", list(
  mongreldb_condition("fm_contains", list(column = 2, pattern = "database performance"))
), limit = 10)

# Vector similarity search (HNSW).
mongreldb_query(db, "embeddings", list(
  mongreldb_condition("ann", list(column = 2, query = list(0.1, 0.2, 0.3), k = 10))))

# Check whether a result was capped by the limit.
res <- mongreldb_query(db, "orders", list(
  mongreldb_condition("range_f64", list(column = 3, min = 0))), limit = 100)
if (isTRUE(res$truncated)) {
  # result set hit the limit; more matches exist on the server.
}
```

## SQL

```r
mongreldb_sql(db, "INSERT INTO orders (id, customer, amount) VALUES (99, 'Zoe', 999.0)")
mongreldb_sql(db, "CREATE TABLE archive AS SELECT * FROM orders WHERE amount > 500")

# Recursive CTEs and window functions.
mongreldb_sql(db, "WITH RECURSIVE r(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM r WHERE n<10) SELECT n FROM r")
mongreldb_sql(db, "SELECT id, ROW_NUMBER() OVER (PARTITION BY customer ORDER BY amount DESC) FROM orders")
```

## User and role management

User and role administration is done through SQL against the `/sql` endpoint.
Quote identifiers and escape literals so caller-supplied names are safe to
interpolate.

```r
mongreldb_sql(db, 'CREATE USER "admin" WITH PASSWORD \'s3cret-pw\'')
mongreldb_sql(db, 'ALTER USER "admin" ADMIN')

mongreldb_sql(db, 'CREATE ROLE "analyst"')
mongreldb_sql(db, 'GRANT SELECT ON orders TO "analyst"')
mongreldb_sql(db, 'GRANT "analyst" TO "alice"')
```

## Error handling

```r
library(MongrelDB)

db <- mongreldb_connect("http://127.0.0.1:8453")

tryCatch(
  mongreldb_put(db, "orders", list(`1` = 1)),    # duplicate PK
  mongreldb_error = function(e) {
    switch(e$kind,
      constraint = message("Constraint: ", e$error_code),  # UNIQUE_VIOLATION
      auth       = message("Not authorized: ", e$message),
      not_found  = message("Not found: ", e$message),
      connection = message("Can't reach daemon: ", e$message),
      message("Error: ", e$message)
    )
  }
)
```

## API reference

### `MongrelDB` package

| Function | Description |
|---|---|
| `mongreldb_connect(url, token, username, password)` | Connect to a daemon |
| `mongreldb_condition(type, params)` | Build a normalized condition |

### Client object (from `mongreldb_connect`)

| Function | Description |
|---|---|
| `mongreldb_health(client)` | Check daemon health |
| `mongreldb_history_retention_epochs(client)` | Current history-retention window (epochs) |
| `mongreldb_earliest_retained_epoch(client)` | Oldest epoch still queryable with `AS OF EPOCH` |
| `mongreldb_set_history_retention_epochs(client, epochs)` | Set the history-retention window; requires admin |
| `mongreldb_tables(client)` | List table names |
| `mongreldb_create_table(client, name, columns, constraints = NULL)` | Create a table, returns table id |
| `mongreldb_drop_table(client, name)` | Drop a table |
| `mongreldb_count(client, table)` | Row count |
| `mongreldb_put(client, table, cells)` | Insert a row |
| `mongreldb_upsert(client, table, cells, update_cells)` | Upsert a row |
| `mongreldb_delete(client, table, row_id)` | Delete by row ID |
| `mongreldb_delete_by_pk(client, table, pk)` | Delete by primary key |
| `mongreldb_query(client, table, conditions, projection, limit, offset)` | Run a paged native query |
| `mongreldb_sql(client, statement)` | Execute SQL |
| `mongreldb_schema(client)` | Full schema catalog |
| `mongreldb_schema_for(client, table)` | Single table schema |
| `mongreldb_transaction(client, ops, idempotency_key)` | Commit a batch atomically |

## Building and testing

The test suite is split into a pure unit suite (no daemon needed) and a live
integration suite.

```sh
R CMD INSTALL .
Rscript -e 'testthat::test_local("tests")'
# or run the unit suite directly:
Rscript -e 'testthat::test_file("tests/testthat/test-json.R")'
```

For the live round-trip suite, start a daemon and point the tests at it:

```sh
MONGRELDB_URL=http://127.0.0.1:8453 Rscript -e 'testthat::test_file("tests/testthat/test-live.R")'
```

## Contributing

Contributions are welcome. Please:

1. Open an issue first for non-trivial changes.
2. Add focused tests near your change, the suite must stay green.
3. Keep R 4.0 as the minimum supported version.
4. Match the existing style: tidyverse-style functions, testthat (3rd edition),
  and the existing package structure.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the full guide.

## History retention

History retention controls how far back `AS OF EPOCH` time-travel queries can
read. Use these functions with `mongreldb-server` 0.48.0+:

```r
window  <- mongreldb_history_retention_epochs(db)
earliest <- mongreldb_earliest_retained_epoch(db)

# Increase the window. Requires admin auth. Increasing retention cannot
# restore history already pruned past the previous earliest epoch.
mongreldb_set_history_retention_epochs(db, window + 10)

rows <- mongreldb_sql(db, sprintf("SELECT id FROM orders AS OF EPOCH %s", earliest))
```

## License

Dual-licensed under the **MIT License** or the **Apache License, Version 2.0**,
at your option. See [MIT](LICENSE-MIT) OR [Apache-2.0](LICENSE-APACHE) for the full text.

`SPDX-License-Identifier: MIT OR Apache-2.0`
