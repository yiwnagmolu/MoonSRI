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
test "audit reports unsupported URLs without using them as file paths" {
  for
    url in [
      "", "?v=1", "/", "/asset/", "/asset/.", "../..", "../../../asset.js", "/%2e%2e/outside.js",
      "/asset%2fsub.js", "/asset%5csub.js", "/asset%00.js", "/bad%xx.js", "/bad%ff.js",
      "/NUL.js", "data:text/javascript,void(0)", "https:app.js", "//",
    ] {
    assert_true(resolve_audit_path("docs/guide", url) is Invalid)
  }
}
