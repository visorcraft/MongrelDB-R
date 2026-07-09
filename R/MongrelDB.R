# MongrelDB R client.
#
# Pure R HTTP client for mongreldb-server. Talks JSON over the Kit
# transaction, query, and SQL endpoints, with a typed error hierarchy and a
# native query builder.
#
# Depends on the 'curl' package for the HTTP transport and 'jsonlite' for
# (de)serialization, both standard CRAN packages.
#
# Usage:
#   library(MongrelDB)
#   db <- mongreldb_connect("http://127.0.0.1:8453")
#   mongreldb_create_table(db, "orders", columns)
#   mongreldb_put(db, "orders", list(`1` = 1, `2` = "Alice", `3` = 99.5))

#' @useDynLib MongrelDB, .registration = TRUE
#' @importFrom curl new_handle handle_setheaders handle_setopt curl_fetch_memory
#' @importFrom jsonlite fromJSON toJSON unbox
"_PACKAGE"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

# Map an HTTP status code to the right error category. Mirrors the other
# MongrelDB clients so callers can match by category across languages.
.KIND_FOR_STATUS <- c(
  "401" = "auth",
  "403" = "auth",
  "404" = "not_found",
  "409" = "constraint"
)

# Friendly aliases translated to the server's canonical wire keys. Mirrors
# the other clients (column -> column_id, min/max -> lo/hi, etc.).
.ALIAS <- c(
  column         = "column_id",
  min            = "lo",
  max            = "hi",
  min_inclusive  = "lo_inclusive",
  max_inclusive  = "hi_inclusive"
)

# ---------------------------------------------------------------------------
# Exception class
# ---------------------------------------------------------------------------

# A mongreldb_error carries a $kind category so callers can match by category
# in a tryCatch. $kind is one of: auth, not_found, constraint, connection,
# query.
new_error <- function(kind, message, error_code = NA_character_,
                      op_index = NA_integer_, status = NA_integer_) {
  structure(
    list(kind = kind, message = message, error_code = error_code,
         op_index = op_index, status = status),
    class = c("mongreldb_error", "error", "condition")
  )
}

# Map an HTTP status code to the right error category.
kind_for_status <- function(status) {
  key <- as.character(status)
  if (key %in% names(.KIND_FOR_STATUS)) .KIND_FOR_STATUS[[key]] else "query"
}
