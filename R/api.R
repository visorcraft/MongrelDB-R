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

#' Get the current history-retention window.
#'
#' @param client A `mongreldb_client`.
#' @return The current retention window in epochs.
#' @export
mongreldb_history_retention_epochs <- function(client) {
  as_u64_scalar(
    request(client, "GET", "history/retention")$history_retention_epochs,
    "history_retention_epochs"
  )
}

#' Get the oldest epoch still queryable with `AS OF EPOCH`.
#'
#' @param client A `mongreldb_client`.
#' @return The oldest retained epoch.
#' @export
mongreldb_earliest_retained_epoch <- function(client) {
  as_u64_scalar(
    request(client, "GET", "history/retention")$earliest_retained_epoch,
    "earliest_retained_epoch"
  )
}

#' Set the history-retention window.
#'
#' @param client A `mongreldb_client`.
#' @param epochs New retention window in epochs.
#' @return The updated retention response from the server.
#' @export
mongreldb_set_history_retention_epochs <- function(client, epochs) {
  epochs <- as_u64_scalar(epochs, "epochs")
  request(client, "PUT", "history/retention", list(history_retention_epochs = epochs))
}

# Aliases matching the names in PLAN.md section 3 (Tier-2 repositories).
# The canonical public names below keep the `_epochs` suffix consistent with
# the server field and the other language clients; these aliases exist only
# for acceptance-criteria parity.

#' @rdname mongreldb_history_retention_epochs
#' @export
mongreldb_history_retention <- mongreldb_history_retention_epochs

#' @rdname mongreldb_set_history_retention_epochs
#' @export
mongreldb_set_history_retention <- mongreldb_set_history_retention_epochs

#' List all table names.
#' @param client A `mongreldb_client`.
#' @return Character vector of table names.
#' @export
mongreldb_tables <- function(client) {
  data <- request(client, "GET", "tables")
  if (is.character(data)) return(data)
  if (is.list(data)) return(unlist(data, use.names = FALSE))
  character(0)
}

#' Create a table.
#'
#' @param client A `mongreldb_client`.
#' @param name Table name.
#' @param columns A list of column descriptor lists. `primary_key` and
#'   `nullable` must be JSON booleans (`TRUE`/`FALSE`).
#' @param constraints Optional table constraints list, including `checks`.
#' @param indexes Optional full secondary-index descriptor list.
#' @return The new table id (integer), or `0L` if none was reported.
#' @export
mongreldb_create_table <- function(client, name, columns, constraints = NULL, indexes = NULL) {
  body <- list(name = name, columns = columns)
  if (!is.null(constraints)) body$constraints <- constraints
  if (!is.null(indexes)) body$indexes <- indexes
  data <- request(client, "POST", "kit/create_table",
    body)
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

#' Structural HLC from durable recovery (0.64+).
#' @param raw List with `physical_micros`, optional `logical`, `node_tiebreaker`.
#' @return List or `NULL` when absent.
#' @export
mongreldb_parse_commit_hlc <- function(raw) {
  if (!is.list(raw) || is.null(raw$physical_micros)) return(NULL)
  list(
    physical_micros = as.numeric(raw$physical_micros),
    logical = as.integer(if (is.null(raw$logical)) 0L else raw$logical),
    node_tiebreaker = as.integer(if (is.null(raw$node_tiebreaker)) 0L else raw$node_tiebreaker)
  )
}

.mongreldb_parse_durable_outcome <- function(raw) {
  if (!is.list(raw)) raw <- list()
  list(
    committed = if ("committed" %in% names(raw)) raw$committed else NULL,
    committed_statements = raw$committed_statements,
    last_commit_epoch = raw$last_commit_epoch,
    last_commit_epoch_text = raw$last_commit_epoch_text,
    last_commit_hlc = mongreldb_parse_commit_hlc(raw$last_commit_hlc),
    first_commit_statement_index = raw$first_commit_statement_index,
    last_commit_statement_index = raw$last_commit_statement_index,
    completed_statements = raw$completed_statements,
    statement_index = raw$statement_index,
    serialization = if (is.null(raw$serialization)) "" else as.character(raw$serialization),
    serialization_state = raw$serialization_state,
    terminal_state = raw$terminal_state
  )
}

#' Decode GET /queries/\{id\} body into a structural status (0.64+).
#' @param raw Decoded JSON list.
#' @return List with `commit_hlc` and `serialization_state` helpers as attributes.
#' @export
mongreldb_parse_query_status <- function(raw) {
  if (!is.list(raw)) raw <- list()
  outcome <- .mongreldb_parse_durable_outcome(raw$outcome)
  durable <- if (is.list(raw$durable)) .mongreldb_parse_durable_outcome(raw$durable) else NULL
  status <- list(
    query_id = if (is.null(raw$query_id)) "" else as.character(raw$query_id),
    status = if (is.null(raw$status)) "" else as.character(raw$status),
    state = if (is.null(raw$state)) "" else as.character(raw$state),
    server_state = if (!is.null(raw$server_state)) as.character(raw$server_state)
      else if (!is.null(raw$state)) as.character(raw$state) else "",
    terminal_state = raw$terminal_state,
    committed = if ("committed" %in% names(raw)) raw$committed else NULL,
    committed_statements = raw$committed_statements,
    last_commit_epoch = raw$last_commit_epoch,
    last_commit_hlc = mongreldb_parse_commit_hlc(raw$last_commit_hlc),
    outcome = outcome,
    durable = durable,
    raw = raw
  )
  class(status) <- c("mongreldb_query_status", "list")
  status
}

#' Authoritative commit HLC from a [mongreldb_parse_query_status()] object.
#' @param status Query status list.
#' @export
mongreldb_commit_hlc <- function(status) {
  if (is.list(status$durable) && !is.null(status$durable$last_commit_hlc)) {
    return(status$durable$last_commit_hlc)
  }
  if (is.list(status$outcome) && !is.null(status$outcome$last_commit_hlc)) {
    return(status$outcome$last_commit_hlc)
  }
  status$last_commit_hlc
}

#' Serialization state preferring nested durable/outcome fields.
#' @param status Query status list.
#' @export
mongreldb_serialization_state <- function(status) {
  if (is.list(status$durable)) {
    if (!is.null(status$durable$serialization_state) &&
        nzchar(as.character(status$durable$serialization_state))) {
      return(as.character(status$durable$serialization_state))
    }
    if (!is.null(status$durable$serialization) &&
        nzchar(as.character(status$durable$serialization))) {
      return(as.character(status$durable$serialization))
    }
  }
  if (is.list(status$outcome)) {
    if (!is.null(status$outcome$serialization_state) &&
        nzchar(as.character(status$outcome$serialization_state))) {
      return(as.character(status$outcome$serialization_state))
    }
    if (!is.null(status$outcome$serialization)) {
      return(as.character(status$outcome$serialization))
    }
  }
  ""
}

#' Text → embed → ANN retrieve (`POST kit/retrieve_text`, 0.64+).
#' @inheritParams mongreldb_put
#' @param embedding_column Integer column id of the embedding.
#' @param text Query text.
#' @param k Optional top-k.
#' @param deadline_ms Optional deadline.
#' @param max_work Optional work budget.
#' @export
mongreldb_retrieve_text <- function(client, table, embedding_column, text,
                                    k = NULL, deadline_ms = NULL, max_work = NULL) {
  if (is.null(table) || !nzchar(table)) {
    stop(new_error("query", "table is required"))
  }
  if (is.null(text) || !nzchar(text)) {
    stop(new_error("query", "text is required"))
  }
  payload <- list(
    table = table,
    embedding_column = as.integer(embedding_column),
    text = text
  )
  if (!is.null(k)) payload$k <- as.integer(k)
  if (!is.null(deadline_ms)) payload$deadline_ms <- as.numeric(deadline_ms)
  if (!is.null(max_work)) payload$max_work <- as.numeric(max_work)
  data <- request(client, "POST", "kit/retrieve_text", payload)
  if (!is.list(data)) return(list(hits = list(), provenance = list()))
  list(
    hits = if (!is.null(data$hits)) data$hits else list(),
    provenance = if (!is.null(data$provenance)) data$provenance else list()
  )
}

#' Retained SQL status for durable recovery (`GET queries/\{query_id\}`).
#' @inheritParams mongreldb_health
#' @param query_id Client/server query id.
#' @export
mongreldb_query_status <- function(client, query_id) {
  if (is.null(query_id) || !nzchar(query_id)) {
    stop(new_error("query", "query_id is required"))
  }
  data <- request(client, "GET", paste0("queries/", encode_segment(query_id)))
  if (!is.list(data)) {
    stop(new_error("query", "query status response was not a JSON object"))
  }
  mongreldb_parse_query_status(data)
}

#' Request cancellation of a running SQL query.
#' @inheritParams mongreldb_query_status
#' @export
mongreldb_cancel_query <- function(client, query_id) {
  if (is.null(query_id) || !nzchar(query_id)) {
    stop(new_error("query", "query_id is required"))
  }
  data <- request(client, "POST",
                  paste0("queries/", encode_segment(query_id), "/cancel"),
                  list())
  if (is.list(data)) data else list()
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
  # produces no rows (INSERT/UPDATE) answers with an empty body, which
  # request() maps to NULL.
  request(client, "POST", "sql", list(sql = statement, format = "json"))
}

#' Run a native query.
#'
#' @inheritParams mongreldb_put
#' @param conditions A list of condition lists from [mongreldb_condition()].
#' @param projection Optional integer vector of column ids to return.
#' @param limit Optional integer row cap.
#' @param offset Optional number of matching rows to skip.
#' @return A list with `rows` and `truncated` (`TRUE` if the result hit the
#'   limit).
#' @export
mongreldb_query <- function(client, table, conditions = list(),
                            projection = NULL, limit = NULL, offset = NULL) {
  payload <- list(table = table)
  if (length(conditions) > 0) payload$conditions <- conditions
  if (!is.null(projection)) payload$projection <- as.list(projection)
  if (!is.null(limit)) payload$limit <- limit
  if (!is.null(offset)) payload$offset <- offset
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
  results <- if (is.list(data) && !is.null(data$results)) data$results else list()
  if (is.list(data) && !is.null(data$epoch)) {
    attr(results, "epoch") <- as_u64_scalar(data$epoch, "epoch")
  }
  results
}
