///|
test "release graph renders waves and constraints in planner order" {
  let page : @rollout.Page = {
    path: "index.html",
    before: Map([("assets/app.js", true)]),
    after: Map([("assets/app.js", false)]),
  }
  let assets : Map[String, @rollout.AssetChange] = Map([
    ("assets/app.js", @rollout.Replace),
  ])
  let plan = @rollout.plan([page], assets)
  let describe = action => {
    release_action_parts(action, Set(["index.html"]), Set(["index.html"]))
  }
  guard render_release_graph([page], assets, plan, "mermaid", describe)
    is Some(mermaid) else {
    fail("expected a mermaid rendering")
  }
  assert_true(mermaid.has_prefix("flowchart LR\n"))
  assert_true(mermaid.contains("n0[\"replace_asset assets/app.js\"]"))
  assert_true(mermaid.contains("n1[\"switch_page index.html\"]"))
  assert_true(mermaid.contains("subgraph wave1\n    n0\n  end"))
  assert_true(mermaid.contains("subgraph wave2\n    n1\n  end"))
  assert_true(mermaid.contains("n0 --> n1"))
  assert_false(mermaid.contains("style"))
  guard render_release_graph([page], assets, plan, "dot", describe) is Some(dot) else {
    fail("expected a dot rendering")
  }
  assert_true(dot.contains("digraph moonsri {"))
  assert_true(dot.contains("n1 [label=\"switch_page index.html\"];"))
  assert_true(dot.contains("subgraph cluster_wave2 {"))
  assert_true(dot.contains("n0 -> n1;"))
  // Node ids must line up between both formats and the planner's ordering.
  guard render_release_graph([page], assets, plan, "not-a-format", describe)
    is None else {
    fail("expected an unknown format to be rejected")
  }
}

///|
test "release graph highlights cycle nodes and skips empty wave blocks" {
  let page : @rollout.Page = {
    path: "index.html",
    before: Map([("assets/app.js", false)]),
    after: Map([("assets/app.js", false)]),
  }
  let assets : Map[String, @rollout.AssetChange] = Map([
    ("assets/app.js", @rollout.Replace),
  ])
  let plan = @rollout.plan([page], assets)
  assert_false(plan.cycle.is_empty())
  let describe = action => {
    release_action_parts(action, Set(["index.html"]), Set(["index.html"]))
  }
  guard render_release_graph([page], assets, plan, "mermaid", describe)
    is Some(mermaid) else {
    fail("expected a mermaid rendering")
  }
  assert_false(mermaid.contains("subgraph"))
  assert_true(mermaid.contains("style n0 fill:#ffcccc"))
  assert_true(mermaid.contains("style n1 fill:#ffcccc"))
  // The cycle repeats its first node at the end of the edge list.
  assert_true(mermaid.contains("n0 --> n1"))
  assert_true(mermaid.contains("n1 --> n0"))
}

///|
test "release graph escapes quotes for both graph languages" {
  let page : @rollout.Page = {
    path: "a\"b.html",
    before: Map([]),
    after: Map([]),
  }
  let plan = @rollout.plan([page], Map([]))
  let describe = action => {
    release_action_parts(action, Set([]), Set(["a\"b.html"]))
  }
  guard render_release_graph([page], Map([]), plan, "mermaid", describe)
    is Some(mermaid) else {
    fail("expected a mermaid rendering")
  }
  assert_true(mermaid.contains("n0[\"publish_page a&quot;b.html\"]"))
  guard render_release_graph([page], Map([]), plan, "dot", describe)
    is Some(dot) else {
    fail("expected a dot rendering")
  }
  assert_true(dot.contains("n0 [label=\"publish_page a\\\"b.html\"];"))
}
