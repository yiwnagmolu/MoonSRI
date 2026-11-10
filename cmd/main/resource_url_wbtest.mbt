///|
test "tag URL validation preserves relative URLs and supports valid HTTP URLs" {
  for
    value in [
      "asset.js", "../assets/app.js?v=1&lang=zh", "/assets/app.js", "HTTPS://example.com/app.js",
      "https://[::1]:8443/app.js", "http://user:pass@example.com:80/app.js", "https://例子.测试/app.js",
    ] {
    assert_true(is_resource_url(value))
  }
  for
    value in [
      "https://@/app.js", "https://example.com:bogus/app.js", "https://example.com:65536/app.js",
      "https://[::1/app.js", "//example.com/app.js", "javascript:alert(1)", "https:///example.com/app.js",
      "hello world.js",
    ] {
    assert_false(is_resource_url(value))
  }
}

///|
test "HTML audit rejects malformed HTTP authorities and keeps local resolution" {
  for
    value in [
      "https://@/app.js", "https://example.com:bogus/app.js", "//example.com:65536/app.js",
      "//[::1/app.js", "//",
    ] {
    assert_true(resolve_audit_path("docs", value) is Invalid)
  }
  for
    value in [
      "https://[::1]:8443/app.js", "//[2001:db8::1]/app.js", "http://user:pass@example.com:80/app.js",
      "//例子.测试/app.js",
    ] {
    assert_true(resolve_audit_path("docs", value) is External)
  }
  assert_true(resolve_audit_path("docs", "app.js?v=2") is Local("docs/app.js"))
}
