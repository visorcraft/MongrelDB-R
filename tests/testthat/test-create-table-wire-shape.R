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

  constraints <- list(
    checks = list(list(
      id = 1,
      name = "ck_status",
      expr = list(IsNotNull = 2)
    ))
  )
  expect_equal(
    mongreldb_create_table(client, "wire_optional", with_optional, constraints),
    7L
  )
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
  expect_equal(optional_payload$constraints$checks[[1]]$name, "ck_status")
  expect_equal(optional_payload$constraints$checks[[1]]$expr$IsNotNull, 2L)

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

testthat::test_that("create_table sends all indexes and embedding source", {
  captured <- list()
  testthat::local_mocked_bindings(
    do_request = function(method, url, headers, content, max_bytes) {
      captured[[1L]] <<- list(content = content)
      list(status_code = 200L, content = charToRaw('{"table_id":1}'))
    },
    .package = "MongrelDB"
  )
  client <- mongreldb_connect("http://127.0.0.1:1")
  columns <- list(
    list(id = 1, name = "id", ty = "int64", primary_key = TRUE),
    list(id = 2, name = "embedding", ty = "embedding(384)", embedding_source = list(
      kind = "configured_model", provider_id = "docs", model_id = "model", model_version = "1"
    ))
  )
  indexes <- list(
    list(name = "bm", column_id = 1, kind = "bitmap"),
    list(name = "fm", column_id = 1, kind = "fm_index"),
    list(name = "ann", column_id = 2, kind = "ann", predicate = "embedding IS NOT NULL",
      options = list(ann = list(m = 24, ef_construction = 96, ef_search = 48,
        quantization = "dense", algorithm = "diskann",
        diskann = list(r = 64, l = 128, beam_width = 8, alpha = 120)))),
    list(name = "range", column_id = 1, kind = "learned_range"),
    list(name = "minhash", column_id = 1, kind = "minhash"),
    list(name = "sparse", column_id = 1, kind = "sparse")
  )
  expect_equal(mongreldb_create_table(client, "search_docs", columns, indexes = indexes), 1L)
  payload <- jsonlite::fromJSON(captured[[1]]$content, simplifyVector = FALSE)
  expect_equal(payload$columns[[2]]$embedding_source$kind, "configured_model")
  expect_equal(vapply(payload$indexes, `[[`, character(1), "kind"),
    c("bitmap", "fm_index", "ann", "learned_range", "minhash", "sparse"))
  expect_equal(payload$indexes[[3]]$options$ann$quantization, "dense")
  expect_equal(payload$indexes[[3]]$options$ann$algorithm, "diskann")
  expect_equal(payload$indexes[[3]]$options$ann$diskann$r, 64)
  expect_equal(payload$indexes[[3]]$predicate, "embedding IS NOT NULL")
})

testthat::test_that("create_table preserves the full static-default matrix", {
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
      list(status_code = 200L, content = charToRaw('{"table_id":11}'))
    },
    .package = "MongrelDB"
  )

  client <- mongreldb_connect("http://127.0.0.1:1")

  cols <- list(
    list(id = 10, name = "s",        ty = "varchar",   primary_key = FALSE, nullable = FALSE, default_value = "hello"),
    list(id = 11, name = "n",        ty = "int64",     primary_key = FALSE, nullable = FALSE, default_value = 42),
    list(id = 12, name = "b",        ty = "bool",      primary_key = FALSE, nullable = FALSE, default_value = TRUE),
    list(id = 13, name = "nl",       ty = "varchar",   primary_key = FALSE, nullable = TRUE,  default_value = NULL),
    list(id = 14, name = "now_lit",  ty = "varchar",   primary_key = FALSE, nullable = FALSE, default_value = "now"),
    list(id = 15, name = "uuid_lit", ty = "varchar",   primary_key = FALSE, nullable = FALSE, default_value = "uuid"),
    list(id = 16, name = "expr",     ty = "timestamp", primary_key = FALSE, nullable = FALSE, default_expr = "now")
  )

  expect_equal(mongreldb_create_table(client, "matrix", cols), 11L)

  payload <- jsonlite::fromJSON(captured[[1]]$content, simplifyVector = FALSE)
  c <- payload$columns
  expect_equal(c[[1]]$default_value, "hello")
  expect_equal(c[[2]]$default_value, 42L)
  expect_equal(c[[3]]$default_value, TRUE)
  expect_null(c[[4]]$default_value)
  expect_equal(c[[5]]$default_value, "now")
  expect_equal(c[[6]]$default_value, "uuid")
  expect_equal(c[[7]]$default_expr, "now")
  expect_false("default_value" %in% names(c[[7]]))
})
