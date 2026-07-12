testthat::test_that("history retention GET uses the right path and parses both keys", {
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
      list(status_code = 200L,
           content = charToRaw('{"history_retention_epochs":100,"earliest_retained_epoch":7}'))
    },
    .package = "MongrelDB"
  )

  client <- mongreldb_connect("http://127.0.0.1:1")

  expect_equal(mongreldb_history_retention_epochs(client), 100)
  expect_equal(captured[[1]]$method, "GET")
  expect_match(captured[[1]]$url, "/history/retention$", perl = TRUE)

  captured <- list()
  expect_equal(mongreldb_earliest_retained_epoch(client), 7)
  expect_equal(captured[[1]]$method, "GET")
  expect_match(captured[[1]]$url, "/history/retention$", perl = TRUE)
})

testthat::test_that("set_history_retention_epochs PUTs exactly history_retention_epochs", {
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
      list(status_code = 200L,
           content = charToRaw('{"history_retention_epochs":200,"earliest_retained_epoch":3}'))
    },
    .package = "MongrelDB"
  )

  client <- mongreldb_connect("http://127.0.0.1:1")
  resp <- mongreldb_set_history_retention_epochs(client, 200L)

  expect_equal(captured[[1]]$method, "PUT")
  expect_match(captured[[1]]$url, "/history/retention$", perl = TRUE)

  body <- jsonlite::fromJSON(captured[[1]]$content, simplifyVector = FALSE)
  expect_equal(body$history_retention_epochs, 200L)
  expect_false("earliest_retained_epoch" %in% names(body))
  expect_equal(resp$history_retention_epochs, 200L)
  expect_equal(resp$earliest_retained_epoch, 3L)
})

testthat::test_that("set_history_retention_epochs rejects overflow and non-whole values", {
  client <- mongreldb_connect("http://127.0.0.1:1")
  err <- tryCatch(mongreldb_set_history_retention_epochs(client, 9007199254740992), error = function(e) e)
  expect_s3_class(err, "mongreldb_error")
  expect_equal(err$kind, "query")

  err2 <- tryCatch(mongreldb_set_history_retention_epochs(client, 1.5), error = function(e) e)
  expect_s3_class(err2, "mongreldb_error")
  expect_equal(err2$kind, "query")
})

testthat::test_that("PLAN.md retention aliases forward to the canonical functions", {
  expect_identical(mongreldb_history_retention, mongreldb_history_retention_epochs)
  expect_identical(mongreldb_set_history_retention, mongreldb_set_history_retention_epochs)
})
