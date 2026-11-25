///|
test "release collection preserves repeated references in a page" {
  let result = read_release_page_pair(
    "browser.html",
    Some("examples/"),
    None,
    Set([]),
  )
  guard result is Ok((refs, [])) else {
    fail("expected to collect browser example")
  }
  assert_eq(refs.length(), 3)
  assert_eq(refs[0].path, "style.css")
  assert_eq(refs[1].path, "hello.js")
  assert_eq(refs[2].path, "hello.js")
  assert_true(refs[1].integrity != refs[2].integrity)
}

///|
test "release references resolve relative bases in their own page directory" {
  let source =
    #|<base href="public/">
    #|<script src="app%20main.js?rev=1#x" integrity="sha384-old"></script>
    #|<script src="app%20main.js?rev=2" integrity="sha384-new"></script>
    #|<script src="/shared.js" integrity="sha384-root"></script>
    #|<script src="https://cdn.example/app.js"></script>
  let supported = Set([])
  for directory in ["first", "中文"] {
    guard parse_release_references(directory + "/index.html", source, supported)
      is Ok(refs) else {
      fail("expected local references")
    }
    assert_eq(refs.length(), 3)
    assert_eq(refs[0].path, directory + "/public/app main.js")
    assert_eq(refs[1].path, refs[0].path)
    assert_eq(refs[0].integrity, "sha384-old")
    assert_eq(refs[1].integrity, "sha384-new")
    assert_eq(refs[2].path, "shared.js")
  }
}

///|
test "release references retain per-declaration failures and invalid local URLs" {
  let supported = Set([])
  let valid = "<script src='app.js' integrity='sha384-ok'></script>"
  for
    entry in [
      (
        "<script src='app.js?next'></script>", "missing integrity for \"app.js\"",
      ),
      (
        "<script src='app.js' integrity='&#9; &#12;'></script>", "missing integrity for \"app.js\"",
      ),
      (
        "<script src='app.js' integrity='sha1-no'></script>", "no supported integrity for \"app.js\"",
      ),
      (
        "<script src='#hash' integrity='sha384-ok'></script>", "invalid URL \"#hash\"",
      ),
      (
        "<script src='../app.js' integrity='sha384-ok'></script>", "invalid URL \"../app.js\"",
      ),
      (
        "<script src='asset%2Fapp.js' integrity='sha384-ok'></script>", "invalid URL \"asset%2Fapp.js\"",
      ),
    ] {
    let (extra, expected) = entry
    guard parse_release_references("index.html", valid + extra, supported)
      is Err(reason) else {
      fail("expected a declaration or URL error")
    }
    assert_eq(reason, expected)
  }
}

///|
test "equal page sources share declarations but each root verifies its own bytes" {
  guard read_release_page_pair(
      "index.html",
      Some("examples/rollout/before/"),
      Some("examples/rollout/before/"),
      Set([]),
    )
    is Ok((before, after)) else {
    fail("expected both page versions")
  }
  guard before.get(1) is Some(previous) && after.get(1) is Some(current) else {
    fail("expected the same script in both snapshots")
  }
  assert_eq(previous.path, current.path)
  assert_eq(previous.integrity, current.integrity)
  let old_files : ReleaseFiles = {
    prefix: "examples/rollout/before/",
    tokens: Map([]),
    matches_by_declaration: Map([]),
  }
  let new_files : ReleaseFiles = {
    prefix: "examples/rollout/overwrite/",
    tokens: Map([]),
    matches_by_declaration: Map([]),
  }
  assert_true(old_files.matches(previous))
  assert_false(new_files.matches(current))
}

///|
test "paired read errors identify the missing endpoint even for shared pages" {
  let pages = ["index.html"]
  for
    entry in [
      ("__missing_snapshot__/", "examples/rollout/before/", "before"),
      ("examples/rollout/before/", "__missing_snapshot__/", "after"),
    ] {
    let (before_root, after_root, side) = entry
    guard collect_release_inputs(before_root, after_root, pages[:], pages[:])
      is Err(reason) else {
      fail("expected the missing page to prevent planning")
    }
    assert_eq(reason, side + " page \"index.html\": read_error")
  }
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
