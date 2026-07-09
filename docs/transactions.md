# Transactions

The MongrelDB daemon commits batched operations atomically. The R client
mirrors that with a `mongreldb_transaction()` function: you build a list of ops
(each a `list(put = ...)`, `list(upsert = ...)`, `list(delete = ...)`, or
`list(delete_by_pk = ...)`) and pass it to `mongreldb_transaction()`, which
flushes the whole batch in a single `/kit/txn` request. Unique, foreign key,
and check constraints are enforced by the engine at commit time, so either
every operation lands or none.

## Basic commit

```r
ops <- list(
  list(put          = list(table = "orders", cells = list(1, 10, 2, "Dave", 3, 50.0))),
  list(put          = list(table = "orders", cells = list(1, 11, 2, "Eve",  3, 75.0))),
  list(delete_by_pk = list(table = "orders", pk = 2))
)
results <- mongreldb_transaction(db, ops)    # atomic: all or nothing
```

`mongreldb_transaction()` returns a list of per-operation result lists. Each
entry reflects the `kind` the engine took (`put`, `deleted`, `not_found`, etc.).

The `cells` field is a flat list of `col_id, value, col_id, value, ...` to
match the on-wire shape for batch ops. When you use `mongreldb_put()` directly,
the client flattens a named list for you.

Note: a row inserted in one transaction is not visible to a `delete_by_pk` in
the *same* transaction. Commit the inserts first, then delete in a follow-up
batch.

## Idempotent commits

Pass an idempotency key as the second argument to make a commit safe to retry.
If the daemon sees the same key again (even after a crash), it returns the
original response instead of replaying the work:

```r
mongreldb_transaction(db, ops, "order-20-create")
```

Keys are opaque, caller-supplied strings. The client does not derive or store
them.

## Constraint handling

If a staged operation violates a constraint, the engine rejects the whole batch
and the client throws a `mongreldb_error` whose `$kind` is `"constraint"`, with
the server's `error_code` (for example, `UNIQUE_VIOLATION`) and, when reported,
the `op_index` of the offending operation:

```r
tryCatch(
  mongreldb_transaction(db, ops),
  mongreldb_error = function(e) {
    message("Constraint violated: ", e$error_code, " (op ", e$op_index, ")")
  }
)
```

See [Errors](errors.md) for the full hierarchy.
