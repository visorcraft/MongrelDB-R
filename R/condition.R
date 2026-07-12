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
#' @importFrom stats setNames
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

# Validate a scalar intended for the server's unsigned 64-bit epoch fields.
# R has no native u64, so we accept whole numbers that are exactly representable
# in a double (<= 2^53 - 1) and reject anything larger to avoid silent rounding.
as_u64_scalar <- function(x, what = "value") {
  if (length(x) != 1L || is.na(x)) {
    stop(new_error("query", sprintf("%s must be a non-missing scalar", what)))
  }
  if (!is.numeric(x) && !is.integer(x)) {
    stop(new_error("query", sprintf("%s must be numeric", what)))
  }
  if (is.nan(x) || is.infinite(x)) {
    stop(new_error("query", sprintf("%s must be finite", what)))
  }
  if (x < 0) {
    stop(new_error("query", sprintf("%s must be non-negative", what)))
  }
  max_exact <- 9007199254740991 # 2^53 - 1
  if (x > max_exact) {
    stop(new_error("query",
      sprintf("%s exceeds the maximum exact u64 value representable in R (%s)",
              what, max_exact)))
  }
  if (x != floor(x)) {
    stop(new_error("query", sprintf("%s must be a whole number", what)))
  }
  as.numeric(x)
}

# Pull the first per-op result out of a txn response.
# The server attaches the commit epoch to the top-level response; preserve it
# as an attribute so callers can issue time-travel queries at the insert epoch.
first_result <- function(data) {
  result <- if (is.list(data) && !is.null(data$results) &&
                is.list(data$results) && length(data$results) > 0) {
    data$results[[1]]
  } else {
    list()
  }
  if (is.list(data) && !is.null(data$epoch)) {
    attr(result, "epoch") <- as_u64_scalar(data$epoch, "epoch")
  }
  result
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
