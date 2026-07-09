# Queries

The Kit `/kit/query` endpoint pushes conditions down to the engine's
specialized indexes for sub-millisecond lookups. The R client exposes those
condition types through `mongreldb_condition()` plus the `mongreldb_query()`
runner.

## Building a query

```r
res <- mongreldb_query(db, "orders", list(
  mongreldb_condition("bitmap_eq", list(column = 2, value = "Alice")),
  mongreldb_condition("range",     list(column = 3, min  = 100.0))
), projection = c(1, 2), limit = 100)

rows      <- res$rows
truncated <- res$truncated
```

Pass a list of conditions (they are AND-ed together), plus optional `projection`
(integer vector of column ids) and `limit` (row cap) arguments. `mongreldb_query()`
returns a list with `rows` and `truncated` (`TRUE` if the result was capped by
the limit).

## Friendly aliases

`mongreldb_condition()` accepts readable parameter names and translates them to
the server's exact on-wire keys before sending:

| Alias | Wire key |
|---|---|
| `column` | `column_id` |
| `min` | `lo` |
| `max` | `hi` |
| `min_inclusive` | `lo_inclusive` |
| `max_inclusive` | `hi_inclusive` |

For full-text conditions (`fm_contains`, `fm_contains_all`), the alias `value`
maps to the wire key `pattern`. The server's canonical keys are also accepted
directly, so you can pass the exact wire shape when that is clearer.

## Condition types

| Type | Use | Example parameters |
|---|---|---|
| `pk` | Exact primary key match | `list(value = 1)` |
| `bitmap_eq` | Equality on a bitmap-indexed column | `list(column = 2, value = "Alice")` |
| `bitmap_in` | IN predicate on a bitmap column | `list(column = 2, values = list("Alice","Bob"))` |
| `range` | Integer range predicate | `list(column = 3, min = 10, max = 100)` |
| `range_f64` | Float range predicate | `list(column = 3, min = 10.0, max = 100.0)` |
| `is_null` | Null check | `list(column = 2)` |
| `is_not_null` | Not-null check | `list(column = 2)` |
| `fm_contains` | Full-text substring (FM-index) | `list(column = 2, pattern = "database")` |
| `fm_contains_all` | All patterns must match | `list(column = 2, patterns = list("database","index"))` |
| `ann` | Dense vector similarity (HNSW) | `list(column = 2, query = list(0.1,0.2,0.3), k = 10)` |
| `sparse_match` | Sparse vector match | `list(column = 2, query = list(...))` |
| `min_hash_similar` | MinHash similarity search | `list(column = 2, query = list(...))` |

## Truncation check

The `$truncated` field of the result tells you whether the result set was
capped by the limit:

```r
res <- mongreldb_query(db, "orders",
  list(mongreldb_condition("range", list(column = 3, min = 0))),
  limit = 100)
if (isTRUE(res$truncated)) {
  # result set hit the limit; more matches exist on the server.
}
```
