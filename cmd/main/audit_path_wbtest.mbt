///|
test "audit URLs resolve against the page directory or deployment root" {
  let directory = "docs/guide"
  assert_true(
    resolve_audit_path(directory, "app.js?v=2#main")
    is Local("docs/guide/app.js"),
  )
  assert_true(
    resolve_audit_path(directory, "../app.js") is Local("docs/app.js"),
  )
  assert_true(
    resolve_audit_path(directory, "/assets/hello%20%E6%9C%88.js")
    is Local("assets/hello 月.js"),
  )
  assert_true(resolve_audit_path(directory, "//cdn.example/app.js") is External)
  assert_true(
    resolve_audit_path(directory, "HTTPS://cdn.example/app.js") is External,
  )
}

///|
test "audit base directories support local URL paths with standard trailing-slash behavior" {
  let page = "docs/guide/index.html"
  assert_eq(audit_base_directory(page, ""), Some("docs/guide"))
  assert_eq(audit_base_directory(page, "/"), Some(""))
  assert_eq(
    audit_base_directory(page, " ../bundle%20files/?v=2 "),
    Some("docs/bundle files"),
  )
  assert_eq(audit_base_directory(page, "/assets/site.html"), Some("assets"))
  assert_eq(audit_base_directory(page, "/assets"), Some(""))
  assert_eq(audit_base_directory(page, ".."), Some("docs"))
  assert_eq(audit_base_directory(page, "?v=1"), Some("docs/guide"))
  assert_eq(audit_base_directory(page, "https://cdn.example/assets/"), None)
  assert_eq(audit_base_directory(page, "/%2e%2e/assets/"), None)
}

///|
test "audit distinguishes directory and current-page URLs from asset files" {
  let directory = "docs/guide"
  assert_true(resolve_audit_path(directory, "/") is Directory(""))
  assert_true(resolve_audit_path(directory, "/asset/") is Directory("asset"))
  assert_true(resolve_audit_path(directory, "/asset/.") is Directory("asset"))
  assert_true(resolve_audit_path(directory, "../..") is Directory(""))
  assert_true(resolve_audit_path(directory, "") is SameDocument)
  assert_true(resolve_audit_path(directory, "?v=1") is SameDocument)
}

///|
test "audit reports unsupported URLs without using them as file paths" {
  for
    url in [
      "../../../asset.js", "/%2e%2e/outside.js", "/asset%2fsub.js", "/asset%5csub.js",
      "/asset%00.js", "/bad%xx.js", "/bad%ff.js", "/NUL.js", "data:text/javascript,void(0)",
      "https:app.js", "//",
    ] {
    assert_true(resolve_audit_path("docs/guide", url) is Invalid)
  }
}
