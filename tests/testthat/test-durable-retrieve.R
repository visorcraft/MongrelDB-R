test_that("query status parses structural HLC without string parsing", {
  fixture <- list(
    query_id = "abcdefabcdefabcdefabcdefabcdefab",
    status = "committed",
    state = "completed",
    server_state = "completed",
    terminal_state = "committed",
    committed = TRUE,
    committed_statements = 1L,
    last_commit_epoch = 17,
    last_commit_hlc = list(
      physical_micros = 1700000000000000,
      logical = 3L,
      node_tiebreaker = 7L
    ),
    outcome = list(
      committed = TRUE,
      last_commit_epoch = 17,
      last_commit_hlc = list(
        physical_micros = 1700000000000000,
        logical = 3L,
        node_tiebreaker = 7L
      ),
      serialization = "succeeded",
      serialization_state = "succeeded",
      terminal_state = "committed"
    ),
    durable = list(
      committed = TRUE,
      last_commit_epoch = 17,
      last_commit_hlc = list(
        physical_micros = 1700000000000000,
        logical = 3L,
        node_tiebreaker = 7L
      ),
      serialization = "succeeded",
      serialization_state = "succeeded",
      terminal_state = "committed"
    )
  )
  status <- mongreldb_parse_query_status(fixture)
  expect_true(isTRUE(status$committed))
  hlc <- mongreldb_commit_hlc(status)
  expect_false(is.null(hlc))
  expect_equal(hlc$physical_micros, 1700000000000000)
  expect_equal(hlc$logical, 3L)
  expect_equal(hlc$node_tiebreaker, 7L)
  expect_equal(mongreldb_serialization_state(status), "succeeded")
  expect_equal(status$outcome$last_commit_epoch, 17)
  expect_null(mongreldb_parse_commit_hlc(NULL))
  expect_null(mongreldb_parse_commit_hlc(list()))
  expect_null(mongreldb_parse_commit_hlc(list(logical = 1L)))
})
