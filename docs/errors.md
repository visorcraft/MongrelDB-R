# Error handling

The R client reports errors as `mongreldb_error` condition objects. Every error
has a `$kind` field (the category) and a `$message`, and prints cleanly when
shown. You match on `$kind` to react to the specific category.

## Error kinds

| `$kind` | Meaning |
|---|---|
| `auth` | HTTP 401 / 403 |
| `not_found` | HTTP 404 |
| `constraint` | HTTP 409, constraint violation at commit |
| `connection` | Network-level failure (refused, DNS, timeout) |
| `query` | HTTP 400 / 500, malformed payloads, JSON failures |

The client signals these with the standard R condition mechanism; wrap calls
in `tryCatch` and match the `mongreldb_error` class to catch them.

## Catching by category

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

## Constraint fields

A `constraint` error carries extra fields:

- `error_code` - the server's error code string, e.g. `UNIQUE_VIOLATION`.
- `op_index` - when reported, the index of the offending operation within the
  batch (useful when a [transaction](transactions.md) commit fails).
- `status` - the HTTP status code.

## Connection failures

A `connection` error is signaled for any network-level problem: connection
refused, DNS lookup failure, or a timeout. The `mongreldb_health()` helper
swallows these and returns `FALSE` instead, which is handy for startup checks:

```r
if (!mongreldb_health(db)) {
  # daemon not reachable; degrade gracefully
}
```

## JSON edge cases

The client refuses to send values that have no valid JSON representation:
`NA`, infinity, and NaN. These signal a `query` error at the client boundary
rather than corrupting data on the server. Malformed UTF-8 is passed through so
the daemon can substitute it.
