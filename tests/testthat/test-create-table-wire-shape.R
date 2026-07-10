testthat::test_that("create_table sends optional column keys only when set", {
  captured <- list()
  testthat::local_mocked_bindings(
    do_request = function(method, url, headers, content, max_bytes) {
      captured[[length(captured) + 1L]] <<- list(
        method = method,
        url = url,
        headers = headers,
        content = content,
        max_bytes = max_bytes
      )
      list(status_code = 200L, content = charToRaw('{"table_id":7}'))
    },
    .package = "MongrelDB"
  )

  client <- mongreldb_connect("http://127.0.0.1:1")

  with_optional <- list(
    list(
      id = 1,
      name = "id",
      ty = "int64",
      primary_key = TRUE,
      nullable = FALSE
    ),
    list(
      id = 2,
      name = "status",
      ty = "enum",
      primary_key = FALSE,
      nullable = FALSE,
      enum_variants = c("draft", "active", "archived"),
      default_value = "draft"
    )
  )

  expect_equal(mongreldb_create_table(client, "wire_optional", with_optional), 7L)
  expect_equal(captured[[1]]$method, "POST")
  expect_match(captured[[1]]$url, "/kit/create_table$", perl = TRUE)
  expect_equal(captured[[1]]$headers[["Content-Type"]], "application/json")
  expect_match(captured[[1]]$content, '"enum_variants"', fixed = TRUE)
  expect_match(captured[[1]]$content, '"default_value"', fixed = TRUE)

  optional_payload <- jsonlite::fromJSON(captured[[1]]$content, simplifyVector = FALSE)
  status_col <- optional_payload$columns[[2]]
  expect_true("enum_variants" %in% names(status_col))
  expect_true("default_value" %in% names(status_col))
  expect_equal(status_col$enum_variants, list("draft", "active", "archived"))
  expect_equal(status_col$default_value, "draft")

  without_optional <- list(
    list(
      id = 1,
      name = "id",
      ty = "int64",
      primary_key = TRUE,
      nullable = FALSE
    ),
    list(
      id = 2,
      name = "name",
      ty = "varchar",
      primary_key = FALSE,
      nullable = FALSE
    )
  )

  expect_equal(mongreldb_create_table(client, "wire_plain", without_optional), 7L)
  expect_no_match(captured[[2]]$content, '"enum_variants"', fixed = TRUE)
  expect_no_match(captured[[2]]$content, '"default_value"', fixed = TRUE)

  plain_payload <- jsonlite::fromJSON(captured[[2]]$content, simplifyVector = FALSE)
  plain_col <- plain_payload$columns[[2]]
  expect_false("enum_variants" %in% names(plain_col))
  expect_false("default_value" %in% names(plain_col))
})
