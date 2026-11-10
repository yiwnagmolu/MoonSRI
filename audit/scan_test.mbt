///|
test "scan finds active static references and decodes HTML attributes" {
  let source =
    #|<!doctype html>
    #|<!-- <script src="comment.js"></script> -->
    #|<script>const example = '<link rel="stylesheet" href="inline.css">';</script>
    #|<script type="application/json" src="data.json"></script>
    #|<template><base href="/inert/"><script src="template.js"></script></template>
    #|<noscript><link rel="stylesheet" href="noscript.css"></noscript>
    #|<script type="MODULE" src="app.js?a=1&amp;b=2" integrity="sha384-known"></script>
    #|<link rel="stylesheet" href="inactive.css" disabled="false">
    #|<link rel="alternate&#9;StyleSheet" href="theme.css">
  let page = @audit.scan(source)
  assert_true(page.base_href is None)
  assert_eq(page.references.length(), 2)
  assert_true(page.references[0].kind is @audit.Script)
  assert_eq(page.references[0].url, "app.js?a=1&b=2")
  assert_true(page.references[0].integrity is Some("sha384-known"))
  assert_true(page.references[1].kind is @audit.Stylesheet)
  assert_eq(page.references[1].url, "theme.css")
  assert_true(page.references[1].integrity is None)
}

///|
test "scan retains the first effective base href" {
  let page = @audit.scan(
    "<base target=_blank><base href=/assets/><base href=/other/>",
  )
  assert_true(page.base_href is Some("/assets/"))
}
