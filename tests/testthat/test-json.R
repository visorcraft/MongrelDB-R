# Pure unit tests for the MongrelDB R client.
#
# No daemon is needed. These tests exercise the JSON (de)serialization
# behavior, the cell-flattening helper, and the condition alias
# normalization, so the wire-format contract stays covered offline.

test_that("JSON encode/decode round-trips scalars", {
  expect_equal(jsonlite::fromJSON(jsonlite::toJSON(42)), 42)
  expect_equal(jsonlite::fromJSON(jsonlite::toJSON(3.14)), 3.14)
  expect_equal(jsonlite::fromJSON(jsonlite::toJSON("hello")), "hello")
  expect_equal(jsonlite::fromJSON(jsonlite::toJSON(TRUE)), TRUE)
  expect_equal(jsonlite::fromJSON(jsonlite::toJSON(FALSE)), FALSE)
})

test_that("JSON encode/decode round-trips containers", {
  expect_equal(jsonlite::fromJSON(jsonlite::toJSON(1:3)), 1:3)
  obj <- list(a = 1, b = 2)
  # jsonlite wraps scalars in JSON arrays, so a round-trip through
  # simplifyVector = FALSE yields nested length-1 lists (e.g. list(a = list(1))).
  # Unwrap each element to recover the original named list across jsonlite 1.x
  # and 2.x.
  dec <- jsonlite::fromJSON(jsonlite::toJSON(obj), simplifyVector = FALSE)
  expect_equal(lapply(dec, unlist), obj)
})

test_that("UTF-8 strings survive a round-trip", {
  flap <- "mångrel"
  # toJSON wraps the scalar in a JSON array; with simplifyVector = FALSE
  # fromJSON returns a length-1 list, so extract the element with [[1]].
  dec <- jsonlite::fromJSON(jsonlite::toJSON(flap), simplifyVector = FALSE)
  expect_equal(dec[[1]], flap)
})

test_that("flatten_cells sorts keys ascending and interleaves", {
  flat <- MongrelDB:::flatten_cells(list(`3` = 99.5, `1` = 1, `2` = "Alice"))
  expect_equal(flat, list(1, 1, 2, "Alice", 3, 99.5))
})

test_that("flatten_cells handles empty and single cells", {
  expect_equal(MongrelDB:::flatten_cells(list()), list())
  expect_equal(MongrelDB:::flatten_cells(list(`1` = "x")), list(1, "x"))
})

test_that("condition aliases map to wire keys", {
  cnd <- mongreldb_condition("range",
    list(column = 3, min = 10.0, max = 100.0))
  expect_equal(cnd, list(range = list(column_id = 3, lo = 10.0, hi = 100.0)))
})

test_that("pk condition passes value through", {
  expect_equal(
    mongreldb_condition("pk", list(value = 42)),
    list(pk = list(value = 42))
  )
})

test_that("fm_contains value alias maps to pattern", {
  expect_equal(
    mongreldb_condition("fm_contains", list(column = 2, value = "database")),
    list(fm_contains = list(column_id = 2, pattern = "database"))
  )
})

test_that("canonical wire keys pass through unchanged", {
  expect_equal(
    mongreldb_condition("range", list(column_id = 3, lo = 1, hi = 9)),
    list(range = list(column_id = 3, lo = 1, hi = 9))
  )
})

test_that("ann condition maps column alias and keeps query/k", {
  expect_equal(
    mongreldb_condition("ann", list(column = 2, query = list(0.1, 0.2, 0.3), k = 10)),
    list(ann = list(column_id = 2, query = list(0.1, 0.2, 0.3), k = 10))
  )
})

test_that("error object carries category and fields", {
  e <- MongrelDB:::new_error("constraint", "dup", "UNIQUE_VIOLATION", 1L, 409L)
  expect_s3_class(e, "mongreldb_error")
  expect_equal(e$kind, "constraint")
  expect_equal(e$error_code, "UNIQUE_VIOLATION")
  # print() writes the kind to stdout; capture it.
  out <- capture_output(print(e))
  expect_match(out, "constraint")
})

test_that("kind_for_status maps status codes", {
  expect_equal(MongrelDB:::kind_for_status(401), "auth")
  expect_equal(MongrelDB:::kind_for_status(403), "auth")
  expect_equal(MongrelDB:::kind_for_status(404), "not_found")
  expect_equal(MongrelDB:::kind_for_status(409), "constraint")
  expect_equal(MongrelDB:::kind_for_status(500), "query")
})

test_that("reject_nonfinite stops on NaN and Inf", {
  expect_error(MongrelDB:::reject_nonfinite(list(Inf)), "NA|NaN|Infinity")
  expect_error(MongrelDB:::reject_nonfinite(list(NaN)), "NA|NaN|Infinity")
  expect_error(MongrelDB:::reject_nonfinite(list(NA)), "NA|NaN|Infinity")
  # Finite values and strings pass through without error.
  expect_no_error(MongrelDB:::reject_nonfinite(list(1, 2, "x")))
})

# Wire-shape conformance: the create_table body must pass enum_variants and
# default_value through verbatim, with no alias translation, and a column
# without those keys must not acquire them on the wire.
test_that("create_table body preserves enum_variants and default_value keys", {
  columns <- list(
    list(id = 1, name = "id",      ty = "int64",   primary_key = TRUE,  nullable = FALSE),
    list(id = 2, name = "label",   ty = "varchar", primary_key = FALSE, nullable = FALSE),
    list(id = 3, name = "amount",  ty = "float64", primary_key = FALSE, nullable = FALSE,
         default_value = 0.5),
    list(
      id = 4, name = "status", ty = "enum",
      primary_key = FALSE, nullable = FALSE,
      enum_variants = list("active", "inactive", "pending"),
      default_value  = "pending"
    ),
    list(id = 5, name = "created_at", ty = "timestamp", primary_key = FALSE,
         nullable = FALSE, default_expr = "now")
  )
  payload <- list(name = "orders", columns = columns)
  body <- MongrelDB:::encode_payload(payload)

  # The two pass-through keys appear verbatim in the JSON, with the exact
  # server-expected spelling.
  expect_match(body, '"enum_variants"', fixed = TRUE)
  expect_match(body, '"default_value"',  fixed = TRUE)
  expect_match(body, '"default_expr"', fixed = TRUE)

  # Round-trip the body and check the nested structure: the enum column
  # keeps its array of variants and its scalar default, with the column
  # id, name, and ty intact.
  dec <- jsonlite::fromJSON(body, simplifyVector = FALSE)
  status_col <- dec$columns[[4]]
  expect_equal(status_col$id,            4)
  expect_equal(status_col$name,          "status")
  expect_equal(status_col$ty,            "enum")
  expect_equal(status_col$default_value, "pending")
  expect_equal(status_col$enum_variants, list("active", "inactive", "pending"))
  expect_equal(dec$columns[[3]]$default_value, 0.5)
  expect_equal(dec$columns[[5]]$default_expr, "now")
})

test_that("create_table body omits enum_variants and default_value when unset", {
  # A column without enum_variants / default_value must not leak those keys
  # onto the wire. encode_payload does not synthesize defaults, so absence
  # in R stays absence in JSON.
  columns <- list(
    list(id = 1, name = "id",     ty = "int64",   primary_key = TRUE,  nullable = FALSE),
    list(id = 2, name = "label",  ty = "varchar", primary_key = FALSE, nullable = FALSE)
  )
  body <- MongrelDB:::encode_payload(list(name = "plain", columns = columns))

  # No column carries either key.
  expect_no_match(body, '"enum_variants"', fixed = TRUE)
  expect_no_match(body, '"default_value"',  fixed = TRUE)

  # And the rest of the column shape is intact.
  dec <- jsonlite::fromJSON(body, simplifyVector = FALSE)
  expect_equal(length(dec$columns), 2L)
  expect_equal(dec$columns[[1]]$name, "id")
  expect_equal(dec$columns[[2]]$name, "label")
})
