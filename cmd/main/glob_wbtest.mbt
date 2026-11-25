///|
test "glob patterns match single-segment wildcards" {
  assert_true(glob_match("assets/*.js", "assets/app.js"))
  assert_true(glob_match("assets/app*.js", "assets/app.v2.js"))
  assert_false(glob_match("assets/app*.js", "assets/other.js"))
  // `*` never crosses a path separator.
  assert_false(glob_match("assets/*.js", "assets/vendor/app.js"))
  assert_true(glob_match("assets/?pp.js", "assets/app.js"))
  assert_false(glob_match("assets/?.js", "assets/app.js"))
  assert_false(glob_match("assets/?pp.js", "assets/aapp.js"))
}

///|
test "glob double-star spans whole segments in both directions" {
  assert_true(glob_match("**/*.css", "assets/site.css"))
  assert_true(glob_match("**/*.css", "site.css"))
  assert_true(glob_match("dist/**/assets/app.js", "dist/assets/app.js"))
  assert_true(glob_match("dist/**/assets/app.js", "dist/a/b/assets/app.js"))
  assert_false(glob_match("dist/**/assets/app.js", "dist/assets/extra.js"))
  // `**` inside a segment degrades to `*`, which still cannot cross slashes.
  assert_false(glob_match("assets/**app.js", "assets/a/bapp.js"))
  assert_true(glob_match("assets/**app.js", "assets/vendor-app.js"))
}

///|
test "glob metacharacters are literal when escaped by other characters" {
  assert_true(glob_match("assets/app.js", "assets/app.js"))
  assert_false(glob_match("assets/app.js", "assets/app.jsx"))
  assert_true(glob_match("中文/*/说明?.md", "中文/指南/说明1.md"))
  assert_true(glob_match("a*b", "a-b"))
}

///|
test "glob patterns reject separators, escapes and reserved characters" {
  for
    pattern in [
      "", "/assets/*.js", "assets//app.js", "assets/", "assets/**/", "../*.js", "assets/*.js/",
      "a\\b.js", "a<b.js", "a:b.js", "a\"b.js", "a|b.js", "a?.js ", "a?.js.", "a?.js\u{001f}",
    ] {
    guard glob_pattern_error(pattern) is Some(_) else {
      fail("expected pattern to be rejected: " + pattern)
    }
  }
  guard glob_pattern_error("assets/**/part-*.js") is None else {
    fail("expected a valid multi-star pattern")
  }
  guard glob_pattern_error("assets/app.v?.js") is None else {
    fail("expected a valid question-mark pattern")
  }
}

///|
test "glob segment matching treats every character position explicitly" {
  // A star may consume nothing, so it also matches an empty segment.
  assert_true(glob_segment_matches("*", ""))
  assert_true(glob_segment_matches("a*", "a"))
  assert_true(glob_segment_matches("*a", "a"))
  assert_true(glob_segment_matches("a*a", "aa"))
  // The trailing 'a' must come from the pattern, not the star.
  assert_false(glob_segment_matches("a*a", "ab"))
  // A question mark must consume exactly one character.
  assert_false(glob_segment_matches("a?", "a"))
  assert_true(glob_segment_matches("a?c", "abc"))
  assert_false(glob_segment_matches("a?c", "ac"))
}
