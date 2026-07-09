# Public API methods for the MongrelDB R client.

#' Check daemon health.
#'
#' Returns `TRUE` on success, `FALSE` on failure. Never throws, so it is safe
#' for startup checks.
#' @param client A `mongreldb_client` from [mongreldb_connect()].
#' @return `TRUE` or `FALSE`.
#' @export
mongreldb_health <- function(client) {
  ok <- tryCatch({
    request(client, "GET", "health")
    TRUE
  }, mongreldb_error = function(e) FALSE)
  ok
}

#' List all table names.
#' @param client A `mongreldb_client`.
#' @return Character vector of table names.
#' @export
mongreldb_tables <- function(client) {
  data <- request(client, "GET", "tables")
  if (is.character(data)) data else character(0)
}

#' Create a table.
#'
#' @param client A `mongreldb_client`.
#' @param name Table name.
#' @param columns A list of column descriptor lists. `primary_key` and
#'   `nullable` must be JSON booleans (`TRUE`/`FALSE`).
#' @return The new table id (integer), or `0L` if none was reported.
#' @export
mongreldb_create_table <- function(client, name, columns) {
  data <- request(client, "POST", "kit/create_table",
    list(name = name, columns = columns))
  if (is.list(data) && !is.null(data$table_id)) as.integer(data$table_id) else 0L
}

#' Drop a table by name.
#' @inheritParams mongreldb_health
#' @param name Table name.
#' @export
mongreldb_drop_table <- function(client, name) {
  request(client, "DELETE", paste0("tables/", encode_segment(name)))
  invisible(NULL)
}

#' Row count for a table.
#' @inheritParams mongreldb_health
#' @param table Table name.
#' @return Integer row count.
#' @export
mongreldb_count <- function(client, table) {
  data <- request(client, "GET", paste0("tables/", encode_segment(table), "/count"))
  if (is.list(data) && !is.null(data$count) && is.numeric(data$count)) {
    as.integer(data$count)
  } else {
    stop(new_error("query", "malformed count response from server"))
  }
}

#' Insert a row.
#'
#' `cells` maps column id to value, e.g. `list(`1` = 1, `2` = "Alice")`.
#' @inheritParams mongreldb_health
#' @param table Table name.
#' @param cells Named list mapping column id to value.
#' @return The per-op result list from the daemon.
#' @export
mongreldb_put <- function(client, table, cells) {
  data <- request(client, "POST", "kit/txn", list(ops = list(
    list(put = list(table = table, cells = flatten_cells(cells)))
  )))
  first_result(data)
}

#' Upsert (insert or update on PK conflict).
#'
#' @inheritParams mongreldb_put
#' @param update_cells Optional named list of cells to update on conflict.
#' @export
mongreldb_upsert <- function(client, table, cells, update_cells = NULL) {
  op <- list(table = table, cells = flatten_cells(cells))
  if (!is.null(update_cells)) {
    op$update_cells <- flatten_cells(update_cells)
  }
  data <- request(client, "POST", "kit/txn", list(ops = list(list(upsert = op))))
  first_result(data)
}

#' Delete a row by its internal row id.
#' @inheritParams mongreldb_put
#' @param row_id Integer row id.
#' @export
mongreldb_delete <- function(client, table, row_id) {
  request(client, "POST", "kit/txn", list(ops = list(
    list(delete = list(table = table, row_id = row_id))
  )))
  invisible(NULL)
}

#' Delete a row by its primary key value.
#' @inheritParams mongreldb_put
#' @param pk Primary key value.
#' @export
mongreldb_delete_by_pk <- function(client, table, pk) {
  request(client, "POST", "kit/txn", list(ops = list(
    list(delete_by_pk = list(table = table, pk = pk))
  )))
  invisible(NULL)
}

#' Execute SQL.
#'
#' Requests the JSON result format, so a SELECT returns a JSON array of row
#' objects keyed by column name. Returns the decoded rows for SELECTs, or
#' `NULL` for statements like INSERT/UPDATE that produce no rows.
#' @inheritParams mongreldb_health
#' @param statement A SQL statement.
#' @export
mongreldb_sql <- function(client, statement) {
  # JSON mode makes the server answer with a JSON array of row objects
  # (column names as keys) instead of Arrow IPC bytes. A statement that
  # produces no rows (INSERT/UPDATE) may still answer with an empty/non-JSON
  # body, so tolerate that and return NULL.
  tryCatch(
    request(client, "POST", "sql", list(sql = statement, format = "json")),
    error = function(e) {
      if (grepl("malformed JSON", conditionMessage(e), ignore.case = TRUE)) {
        NULL
      } else {
        stop(e)
      }
    }
  )
}

#' Run a native query.
#'
#' @inheritParams mongreldb_put
#' @param conditions A list of condition lists from [mongreldb_condition()].
#' @param projection Optional integer vector of column ids to return.
#' @param limit Optional integer row cap.
#' @return A list with `rows` and `truncated` (`TRUE` if the result hit the
#'   limit).
#' @export
mongreldb_query <- function(client, table, conditions = list(),
                            projection = NULL, limit = NULL) {
  payload <- list(table = table)
  if (length(conditions) > 0) payload$conditions <- conditions
  if (!is.null(projection)) payload$projection <- as.list(projection)
  if (!is.null(limit)) payload$limit <- limit
  data <- request(client, "POST", "kit/query", payload)
  if (!is.list(data)) return(list(rows = list(), truncated = FALSE))
  list(
    rows      = if (!is.null(data$rows)) data$rows else list(),
    truncated = isTRUE(data$truncated)
  )
}

#' Full schema catalog.
#'
#' @inheritParams mongreldb_health
#' @return Named list of table descriptors.
#' @export
mongreldb_schema <- function(client) {
  data <- request(client, "GET", "kit/schema")
  if (is.list(data) && !is.null(data$tables)) data$tables else list()
}

#' Descriptor for a single table.
#' @inheritParams mongreldb_count
#' @export
mongreldb_schema_for <- function(client, table) {
  data <- request(client, "GET", paste0("kit/schema/", encode_segment(table)))
  if (is.list(data)) data else list()
}

#' Commit a batch transaction atomically.
#'
#' @inheritParams mongreldb_health
#' @param ops A list of operation lists (`list(put = ...)`,
#'   `list(upsert = ...)`, `list(delete = ...)`, `list(delete_by_pk = ...)`).
#' @param idempotency_key Optional opaque string for safe retries.
#' @return List of per-operation result objects.
#' @export
mongreldb_transaction <- function(client, ops, idempotency_key = NULL) {
  payload <- list(ops = ops)
  if (!is.null(idempotency_key)) payload$idempotency_key <- idempotency_key
  data <- request(client, "POST", "kit/txn", payload)
  if (is.list(data) && !is.null(data$results)) data$results else list()
}
