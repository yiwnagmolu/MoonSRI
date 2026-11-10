///|
fn plan_script(
  url : String,
  path : String?,
  suffix : String,
  integrity : String?,
) -> PlanResource {
  { kind: "script", url, path, suffix, integrity, }
}

///|
test "HTML diff pairs local URL aliases and reports effective integrity changes" {
  let old = plan_script(
    "../app.js?v=1",
    Some("app.js"),
    "?v=1",
    Some("sha384-A"),
  )
  let absolute = plan_script(
    "/app.js?v=1",
    Some("app.js"),
    "?v=1",
    Some("sha384-A"),
  )
  let unchanged = diff_plan([old], [absolute])
  assert_false(unchanged.has_changes())
  let changed = diff_plan([old], [{ ..absolute, integrity: Some("sha384-B"), }])
  assert_true(changed.has_changes())
  assert_eq(changed.integrity_changed, [(0, 0)])
  assert_eq(changed.added, [])
  assert_eq(changed.removed, [])
  assert_false(changed.order_changed)
}

///|
test "HTML diff distinguishes resource kind, URL suffix and external URLs" {
  let script = plan_script("/app.js?v=1", Some("app.js"), "?v=1", None)
  let external = plan_script("https://cdn.example/app.js", None, "", None)
  assert_false(
    diff_plan([external], [
      { ..external, url: " \thttps://cdn.example/app.js\n", },
    ]).has_changes(),
  )
  let changed = diff_plan([script, external], [
    { ..script, kind: "stylesheet", },
    { ..script, url: "/app.js?v=2", suffix: "?v=2", },
    { ..external, url: "https://cdn.example/main.js", },
  ])
  assert_eq(changed.added, [0, 1, 2])
  assert_eq(changed.removed, [0, 1])
  assert_eq(changed.integrity_changed, [])
  assert_false(changed.order_changed)
}

///|
test "HTML diff retains duplicate occurrences and compares shared order" {
  let app = plan_script("/app.js", Some("app.js"), "", None)
  let main = plan_script("/main.js", Some("main.js"), "", None)
  let extra = plan_script("/extra.js", Some("extra.js"), "", None)
  let forward = diff_plan([app, main, app, app], [extra, main, app, app])
  assert_eq(forward.added, [0])
  assert_eq(forward.removed, [3])
  assert_eq(forward.integrity_changed, [])
  assert_true(forward.order_changed)
  let reverse = diff_plan([app, main, app], [extra, app, main, app, app])
  assert_eq(reverse.added, [0, 4])
  assert_eq(reverse.removed, [])
  assert_false(reverse.order_changed)
}
