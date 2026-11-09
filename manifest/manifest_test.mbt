///|
test "round trips paths with spaces, quotes and non-ASCII characters" {
  let assets = Map([("assets/\u{4e2d} \"demo\".js", "sha384-test")])
  let parsed = @manifest.parse(@manifest.encode(assets))
  assert_eq(parsed.get("assets/\u{4e2d} \"demo\".js"), Some("sha384-test"))
}

///|
test "rejects duplicate, empty and non-string manifest entries" {
  for
    invalid in [
      "{}", "[]", "{\"a\":\"one\",\"a\":\"two\"}", "{\"\":\"sha384-test\"}", "{\"a\":null}",
      "{\"a\\u0000b\":\"sha384-test\"}",
    ] {
    let rejected = try {
      ignore(@manifest.parse(invalid))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
