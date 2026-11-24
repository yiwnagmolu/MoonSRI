///|
test "release collection preserves repeated references in a page" {
  let pages = ["browser.html"]
  let result = load_release_pages("examples/", pages[:], Set([]))
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
  let result = collect_release_inputs(
    "examples/",
    "examples/",
    pages[:],
    pages[:],
  )
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

///|
test "new page uses only the after snapshot and publishes its assets" {
  let before_pages : Array[String] = []
  let after_pages = ["index.html"]
  let result = collect_release_inputs(
    "__missing_snapshot__/",
    "examples/rollout/versioned/",
    before_pages[:],
    after_pages[:],
  )
  guard result is Ok((pages, assets, retained)) else {
    fail("new page should not read from the before snapshot")
  }
  assert_eq(pages.length(), 1)
  assert_eq(pages[0].path, "index.html")
  assert_true(pages[0].before.is_empty())
  assert_true(pages[0].after.get("assets/app.v2.js") is Some(false))
  assert_true(assets.get("assets/app.v2.js") is Some(@rollout.Publish))
  assert_true(assets.get("assets/site.css") is Some(@rollout.Publish))
  assert_true(retained.is_empty())
}

///|
test "retired page keeps its old-only assets without reading the after snapshot" {
  let before_pages = ["index.html"]
  let after_pages : Array[String] = []
  let result = collect_release_inputs(
    "examples/rollout/before/",
    "__missing_snapshot__/",
    before_pages[:],
    after_pages[:],
  )
  guard result is Ok((pages, assets, retained)) else {
    fail("retired page should not read from the after snapshot")
  }
  assert_eq(pages.length(), 1)
  assert_eq(pages[0].path, "index.html")
  assert_true(pages[0].after.is_empty())
  assert_true(pages[0].before.get("assets/app.js") is Some(true))
  assert_true(assets.is_empty())
  assert_eq(retained, ["assets/app.js", "assets/site.css"])
}

///|
test "mixed pages produce a sorted union and exclude still-referenced assets from retention" {
  let before_pages = ["index.html", "hours/index.html"]
  let after_pages = ["index.html"]
  let result = collect_release_inputs(
    "examples/rollout/before/",
    "examples/rollout/versioned/",
    before_pages[:],
    after_pages[:],
  )
  guard result is Ok((pages, assets, retained)) else {
    fail("expected to collect mixed release pages")
  }
  assert_eq(pages.length(), 2)
  assert_eq(pages[0].path, "hours/index.html")
  assert_true(pages[0].after.is_empty())
  assert_eq(pages[1].path, "index.html")
  assert_true(assets.get("assets/app.v2.js") is Some(@rollout.Publish))
  assert_eq(retained, ["assets/app.js"])
}

///|
test "release comparison reuses qualified SHA-512 tokens from both snapshots" {
  let path = "already-hashed.js"
  let key = (path, @sri.Sha512)
  let before : ReleaseFiles = {
    prefix: "",
    tokens: Map([(key, "sha512-old")]),
    matches_by_declaration: Map([]),
  }
  let after : ReleaseFiles = {
    prefix: "",
    tokens: Map([(key, "sha512-old")]),
    matches_by_declaration: Map([]),
  }
  assert_true(before.same_asset(after, path))
  after.tokens[key] = "sha512-new"
  assert_false(before.same_asset(after, path))
}

///|
test "release matching caches each declaration's verdict per snapshot and asset" {
  let files : ReleaseFiles = {
    prefix: "__missing_snapshot__/",
    tokens: Map([(("app.js", @sri.Sha384), "sha384-old")]),
    matches_by_declaration: Map([]),
  }
  let original : ReleaseRef = { path: "app.js", integrity: "sha384-old", }
  let different : ReleaseRef = { path: "app.js", integrity: "sha384-new", }
  assert_true(files.matches(original))
  assert_false(files.matches(different))
  files.tokens.clear()
  assert_true(files.matches(original))
  assert_false(files.matches(different))
  let missing : ReleaseRef = { path: "other.js", integrity: "sha384-old", }
  let unavailable = files.matches(missing) catch { _ => true }
  assert_true(unavailable)
  assert_true(
    files.matches_by_declaration.get((missing.path, missing.integrity)) is None,
  )
}
