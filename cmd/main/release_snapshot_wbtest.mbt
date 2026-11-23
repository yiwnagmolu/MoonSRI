///|
test "release collection preserves repeated references in a page" {
  let pages = ["browser.html"]
  let result = load_release_pages("examples/", pages[:])
  guard result is Ok(found) && found.get("browser.html") is Some(refs) else {
    fail("expected to collect browser example")
  }
  assert_eq(refs.length(), 3)
  assert_eq(refs[0].path, "style.css")
  assert_eq(refs[1].path, "hello.js")
  assert_eq(refs[2].path, "hello.js")
  assert_true(refs[1].integrity != refs[2].integrity)
}

///|
test "release collection rejects an endpoint with an incorrect declaration" {
  let pages = ["browser.html"]
  let result = collect_release_inputs("examples/", "examples/", pages[:])
  guard result is Err(reason) else {
    fail("expected a bad endpoint declaration to prevent planning")
  }
  assert_true(reason.contains("browser.html"))
  assert_true(reason.contains("hello.js"))
  assert_true(reason.contains("integrity mismatch"))
}

///|
test "release paths reject files that must also be directories" {
  let all = Set(["index.html", "assets/app.js", "assets/app.js/v2.js"])
  let paths = ["index.html", "assets/app.js", "assets/app.js/v2.js"]
  assert_true(
    release_path_conflict(paths, all)
    is Some(("assets/app.js", "assets/app.js/v2.js")),
  )
  let unrelated = ["index.html", "assets/app.js", "assets/app.js-other/v2.js"]
  let all_unrelated = Set(unrelated)
  assert_true(release_path_conflict(unrelated, all_unrelated) is None)
}
