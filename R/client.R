# Client connection, transport, and public API.

# Construct a new client. Internal; callers use mongreldb_connect().
new_client <- function(url, auth_header = NULL) {
  structure(
    list(
      url          = sub("/+$", "", url),
      auth_header  = auth_header,
      handle_pool  = NULL
    ),
    class = "mongreldb_client"
  )
}

# Custom print method that redacts the auth_header so that print(db) or
# str(db) does not leak the Bearer token or base64-encoded Basic credentials
# into logs or the console.
print.mongreldb_client <- function(x, ...) {
  cat("<MongrelDB client>\n")
  cat("  URL:", x$url, "\n")
  cat("  Auth:", if (is.null(x$auth_header)) "none" else "[redacted]", "\n")
  invisible(x)
}

#' Connect to a running mongreldb-server daemon.
#'
#' @param url Base URL of the daemon, e.g. `"http://127.0.0.1:8453"`.
#' @param token Optional bearer token for `--auth-token` mode.
#' @param username Optional username for `--auth-users` HTTP Basic mode.
#' @param password Optional password for HTTP Basic mode.
#' @return A `mongreldb_client` object to pass to the other functions.
#' @export
mongreldb_connect <- function(url, token = NULL, username = NULL,
                              password = NULL) {
  auth_header <- NULL
  if (!is.null(token)) {
    auth_header <- paste("Bearer", token)
  } else if (!is.null(username)) {
    creds <- paste0(username, ":", if (is.null(password)) "" else password)
    auth_header <- paste("Basic",
      base64enc::base64encode(charToRaw(creds)))
  }
  new_client(url, auth_header)
}

# Decode the daemon's {"error":{"message":...,"code":...,"op_index":...}}
# envelope when present. Returns a list(message, code, op_index).
parse_error_envelope <- function(body) {
  if (is.null(body) || !nzchar(body)) {
    return(list(message = body, code = NA, op_index = NA))
  }
  decoded <- tryCatch(
    jsonlite::fromJSON(body, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (is.null(decoded) || !is.list(decoded)) {
    return(list(message = body, code = NA, op_index = NA))
  }
  err <- decoded$error
  if (is.list(err)) {
    list(
      message  = if (is.character(err$message))  err$message  else body,
      code     = if (is.character(err$code))     err$code     else NA_character_,
      op_index = if (is.numeric(err$op_index))   as.integer(err$op_index) else NA_integer_
    )
  } else if (is.character(err)) {
    list(message = err, code = NA, op_index = NA)
  } else {
    list(message = body, code = NA, op_index = NA)
  }
}

# Core request helper. Returns the decoded JSON body (or NULL for empty
# bodies). Throws a mongreldb_error of the appropriate category for non-2xx
# or network failures.
request <- function(client, method, path, payload = NULL) {
  url <- paste0(client$url, "/", path)

  headers <- c("Accept" = "application/json", "Connection" = "close")
  if (!is.null(client$auth_header)) {
    headers["Authorization"] <- client$auth_header
  }

  content <- NULL

  # Response size cap (256 MB). Passed to libcurl via CURLOPT_MAXFILESIZE
  # in do_request so the transfer aborts before buffering oversized bodies.
  max_bytes <- 256L * 1024L * 1024L # 268435456 bytes

  if (!is.null(payload)) {
    content <- encode_payload(payload)
    headers["Content-Type"] <- "application/json"
    headers["Content-Length"] <- as.character(nchar(content, type = "bytes"))
  }

  resp <- tryCatch(
    do_request(method, url, headers, content, max_bytes),
    error = function(e) {
      # Network-level failures (connection refused, DNS, timeout) become a
      # connection error so callers can distinguish them from responses.
      stop(new_error("connection",
        paste0("network error talking to ", client$url, ": ",
               conditionMessage(e))))
    }
  )

  status <- resp$status_code
  body <- rawToChar(resp$content)

  # Belt-and-suspenders check: libcurl already aborted oversized transfers
  # via CURLOPT_MAXFILESIZE in do_request; this catches anything that slips
  # through (non-libcurl transports, missing Content-Length).
  if (length(resp$content) > max_bytes) {
    stop(new_error("query",
      sprintf("response body exceeds %d bytes (%d bytes)",
              max_bytes, length(resp$content))))
  }

  if (is.na(status) || status < 200 || status >= 300) {
    env <- parse_error_envelope(body)
    message <- env$message
    if (is.na(message) || !nzchar(message)) {
      message <- sprintf("Server error (%s)", status)
    }
    stop(new_error(kind_for_status(status), message, env$code,
                   env$op_index, status))
  }

  if (!nzchar(body)) return(NULL)
  # The client requests JSON result formats, so a non-empty body that is not
  # valid JSON is a protocol error, not a silent NULL.
  tryCatch(
    jsonlite::fromJSON(body, simplifyVector = FALSE),
    error = function(e) {
      stop(new_error("query",
        paste0("malformed JSON response from server: ",
               conditionMessage(e))))
    }
  )
}

# Perform the HTTP request via curl. Returns list(status_code, content = raw).
# max_bytes is passed through to libcurl via CURLOPT_MAXFILESIZE so the
# transfer itself is aborted when the response exceeds the limit, rather than
# only checking after the whole body has been buffered into memory.
do_request <- function(method, url, headers, content, max_bytes) {
  h <- curl::new_handle()
  curl::handle_setheaders(h, .list = as.list(headers))
  # Set a connect + overall timeout so a hung daemon cannot block forever.
  curl::handle_setopt(h,
    connecttimeout = 30L,
    timeout        = 60L,
    # Real streaming size guard: tell libcurl to abort the transfer as soon as
    # the response body exceeds the cap, instead of buffering it all first.
    maxfilesize    = max_bytes
  )
  if (!is.null(content)) {
    curl::handle_setopt(h,
      customrequest = method,
      postfields    = content
    )
  } else if (method != "GET") {
    curl::handle_setopt(h, customrequest = method)
  }
  curl::curl_fetch_memory(url, handle = h)
}

# Percent-encode a single URL path segment so a table name containing '/',
# '?', '#', or spaces cannot inject extra segments or break routing.
# utils::URLencode with reserved = TRUE encodes everything non-unreserved.
encode_segment <- function(segment) {
  utils::URLencode(as.character(segment), reserved = TRUE)
}

# Encode a payload to compact JSON, rejecting non-finite values first.
encode_payload <- function(payload) {
  reject_nonfinite(payload)
  jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null",
                   na = "null")
}

# Recursively walk a payload and stop with a query error if any numeric value
# is NA, NaN, or Inf/(-Inf). These have no valid JSON representation;
# rejecting them here keeps the request from corrupting data on the server.
reject_nonfinite <- function(x) {
  if (is.list(x)) {
    for (elt in x) reject_nonfinite(elt)
    return(invisible(NULL))
  }
  if (is.numeric(x)) {
    if (any(is.na(x) | is.nan(x) | is.infinite(x))) {
      stop(new_error("query",
        "cannot JSON-encode NA, NaN, or Infinity"))
    }
  }
  # Logical NA (the default `NA` literal is type logical) also has no JSON
  # representation and must be rejected like numeric NA; is.logical catches it
  # since the is.numeric branch above only handles numeric values.
  if (is.logical(x)) {
    if (any(is.na(x))) {
      stop(new_error("query",
        "cannot JSON-encode NA, NaN, or Infinity"))
    }
  }
  invisible(NULL)
}
