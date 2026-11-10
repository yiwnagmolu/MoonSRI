///|
test "portable asset paths allow spaces and Unicode in ordinary names" {
  for path in ["index.html", "assets/脚本 bundle.js", ".cache/COM10.js"] {
    assert_true(is_portable_relative_path(path))
  }
}

///|
test "portable asset paths exclude ambiguous or reserved path components" {
  for
    path in [
      "", "/asset.js", "assets//app.js", "assets/../app.js", "assets /app.js", "assets/app?.js",
      "assets/control\u{0000}.js", "assets/back\\slash.js", "assets/NUL.js", "assets/com¹.js",
      "assets/lpt9.css",
    ] {
    assert_false(is_portable_relative_path(path))
  }
}
