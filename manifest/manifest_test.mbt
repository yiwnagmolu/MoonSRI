///|
test "round trips paths with spaces, quotes and non-ASCII characters" {
  let assets = Map([("assets/\u{4e2d} \"demo\".js", "sha384-test")])
  let parsed = @manifest.parse(@manifest.encode(assets))
  assert_eq(parsed.get("assets/\u{4e2d} \"demo\".js"), Some("sha384-test"))
}

///|
test "manifest diff lists only changes in lexical path order" {
  let before = Map([("z.js", "removed"), ("same.css", "same"), ("b.js", "old")])
  let after = Map([("b.js", "updated"), ("same.css", "same"), ("a.css", "new")])
  let changes = @manifest.diff(before, after)
  assert_eq(changes.length(), 3)
  assert_true(changes[0] is @manifest.Added("a.css", "new"))
  assert_true(changes[1] is @manifest.Changed("b.js", "old", "updated"))
  assert_true(changes[2] is @manifest.Removed("z.js", "removed"))
  assert_true(@manifest.diff(before, before).is_empty())
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
