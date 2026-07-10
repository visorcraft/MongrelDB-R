# Extracted from test-json.R:85

# test -------------------------------------------------------------------------
e <- MongrelDB:::new_error("constraint", "dup", "UNIQUE_VIOLATION", 1L, 409L)
expect_s3_class(e, "mongreldb_error")
expect_equal(e$kind, "constraint")
expect_equal(e$error_code, "UNIQUE_VIOLATION")
out <- capture_output(print(e))
expect_match(out, "constraint")
