# Condition builder and internal helpers.

#' Build a normalized condition for [mongreldb_query()].
#'
#' Friendly aliases (`column`, `min`, `max`) are translated to the server's
#' on-wire keys (`column_id`, `lo`, `hi`).
#'
#' @param type Condition type, e.g. `"pk"`, `"range"`, `"bitmap_eq"`.
#' @param params Named list of parameters for the condition.
#' @return A condition list of the form `list(<type> = <normalized params>)`.
#' @export
mongreldb_condition <- function(type, params) {
  stats::setNames(list(normalize_condition(type, params)), type)
}

# Translate friendly aliases for one condition into wire keys.
normalize_condition <- function(cond_type, params) {
  out <- list()
  for (key in names(params)) {
    resolved <- key
    if (key %in% names(.ALIAS)) {
      resolved <- .ALIAS[[key]]
    }
    if ((cond_type == "fm_contains" || cond_type == "fm_contains_all") &&
        key == "value") {
      resolved <- "pattern"
    }
    out[[resolved]] <- params[[key]]
  }
  out
}

# Null-coalescing operator (small helper).
`%||%` <- function(a, b) if (is.null(a)) b else a

# Flatten list(`1` = value, `2` = value) into c(1, value, 2, value) to match
# the on-wire shape for batch ops. Column ids sorted ascending.
flatten_cells <- function(cells) {
  if (length(cells) == 0) return(list())
  keys <- as.integer(names(cells))
  ord <- order(keys)
  flat <- list()
  for (i in seq_along(ord)) {
    flat <- c(flat, list(keys[ord[i]], cells[[ord[i]]]))
  }
  flat
}

# Pull the first per-op result out of a txn response.
first_result <- function(data) {
  if (is.list(data) && !is.null(data$results) &&
      is.list(data$results) && length(data$results) > 0) {
    data$results[[1]]
  } else {
    list()
  }
}

# Pretty-print method so mongreldb_error reads cleanly when printed.
#' @export
print.mongreldb_error <- function(x, ...) {
  cat(sprintf("mongreldb_error(%s): %s\n", x$kind, x$message))
  if (!is.na(x$error_code)) {
    extra <- paste0(" [code=", x$error_code)
    if (!is.na(x$op_index)) extra <- paste0(extra, ", op_index=", x$op_index)
    extra <- paste0(extra, "]")
    cat(extra, "\n")
  }
  invisible(x)
}
