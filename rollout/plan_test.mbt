///|
test "new assets precede pages and changed assets follow old users" {
  let plan = @rollout.plan(
    [
      {
        path: "index.html",
        before: Map([("old.js", false)]),
        after: Map([("new.js", false)]),
      },
      {
        path: "guide.html",
        before: Map([("old.js", false)]),
        after: Map([("new.js", false)]),
      },
    ],
    Map([("old.js", @rollout.Replace), ("new.js", @rollout.Publish)]),
  )
  assert_eq(plan.waves, [
    [@rollout.PublishAsset("new.js")],
    [@rollout.SwitchPage("guide.html"), @rollout.SwitchPage("index.html")],
    [@rollout.ReplaceAsset("old.js")],
  ])
  assert_eq(plan.cycle, [])
  assert_eq(plan.constraints, [
    (@rollout.PublishAsset("new.js"), @rollout.SwitchPage("guide.html")),
    (@rollout.PublishAsset("new.js"), @rollout.SwitchPage("index.html")),
    (@rollout.SwitchPage("guide.html"), @rollout.ReplaceAsset("old.js")),
    (@rollout.SwitchPage("index.html"), @rollout.ReplaceAsset("old.js")),
  ])
}

///|
test "multi-page multi-asset cycle has a closed directed witness" {
  let plan = @rollout.plan(
    [
      {
        path: "a.html",
        before: Map([("a.js", false)]),
        after: Map([("b.js", false)]),
      },
      {
        path: "b.html",
        before: Map([("b.js", false)]),
        after: Map([("a.js", false)]),
      },
      { path: "unrelated.html", before: Map([]), after: Map([]), },
    ],
    Map([("a.js", @rollout.Replace), ("b.js", @rollout.Replace)]),
  )
  assert_eq(plan.waves, [[@rollout.SwitchPage("unrelated.html")]])
  assert_eq(plan.cycle, [
    @rollout.ReplaceAsset("a.js"),
    @rollout.SwitchPage("b.html"),
    @rollout.ReplaceAsset("b.js"),
    @rollout.SwitchPage("a.html"),
    @rollout.ReplaceAsset("a.js"),
  ])
  for index = 0; index + 1 < plan.cycle.length(); index = index + 1 {
    assert_true(
      plan.constraints.contains((plan.cycle[index], plan.cycle[index + 1])),
    )
  }
}

///|
test "compatible digests remove constraints and unchanged assets are retained" {
  let plan = @rollout.plan(
    [
      {
        path: "index.html",
        before: Map([("app.js", true), ("kept.js", false)]),
        after: Map([("app.js", true), ("kept.js", false)]),
      },
    ],
    Map([("app.js", @rollout.Replace)]),
  )
  assert_eq(plan.waves, [
    [@rollout.ReplaceAsset("app.js"), @rollout.SwitchPage("index.html")],
  ])
  assert_eq(plan.constraints, [])
  assert_eq(plan.cycle, [])
}

///|
test "incompatible same-path replacement forms a two-action cycle" {
  let plan = @rollout.plan(
    [
      {
        path: "index.html",
        before: Map([("app.js", false)]),
        after: Map([("app.js", false)]),
      },
    ],
    Map([("app.js", @rollout.Replace)]),
  )
  assert_eq(plan.waves, [])
  assert_eq(plan.cycle, [
    @rollout.ReplaceAsset("app.js"),
    @rollout.SwitchPage("index.html"),
    @rollout.ReplaceAsset("app.js"),
  ])
}

///|
test "page order and map insertion order do not change the plan" {
  let first : @rollout.Page = {
    path: "first.html",
    before: Map([("z.js", false), ("a.js", false)]),
    after: Map([("b.js", false), ("c.js", false)]),
  }
  let second : @rollout.Page = {
    path: "second.html",
    before: Map([("a.js", false), ("z.js", false)]),
    after: Map([("c.js", false), ("b.js", false)]),
  }
  let assets = Map([
    ("z.js", @rollout.Replace),
    ("c.js", @rollout.Publish),
    ("a.js", @rollout.Replace),
    ("b.js", @rollout.Publish),
  ])
  let original = @rollout.plan([second, first], assets)
  let reordered = @rollout.plan(
    [
      {
        ..first,
        before: Map([("a.js", false), ("z.js", false)]),
        after: Map([("c.js", false), ("b.js", false)]),
      },
      {
        ..second,
        before: Map([("z.js", false), ("a.js", false)]),
        after: Map([("b.js", false), ("c.js", false)]),
      },
    ],
    Map([
      ("b.js", @rollout.Publish),
      ("a.js", @rollout.Replace),
      ("c.js", @rollout.Publish),
      ("z.js", @rollout.Replace),
    ]),
  )
  assert_eq(original, reordered)
  assert_eq(@rollout.plan([], Map([])).waves, [])
}

///|
// Model each intermediate deployment directly. Pages use their active version's
// declarations, and an opposite-version asset needs the stored compatibility.
fn accepts_every_state(
  pages : Array[@rollout.Page],
  order : Array[Int32],
) -> Bool {
  let replaced = [false, false]
  let switched = [false, false]
  let asset_names = ["a.js", "b.js"]
  for action in order {
    if action < 2 {
      replaced[action] = true
    } else {
      switched[action - 2] = true
    }
    for page, definition in pages {
      let references = if switched[page] {
        definition.after
      } else {
        definition.before
      }
      for asset, name in asset_names {
        if replaced[asset] != switched[page] && !references[name] {
          return false
        }
      }
    }
  }
  true
}

///|
test "two-page two-asset plans match all 256 compatibility graphs and 24 deployment orders" {
  let orders : Array[Array[Int32]] = []
  for first in 0..<4 {
    for second in 0..<4 {
      for third in 0..<4 {
        for fourth in 0..<4 {
          if first != second &&
            first != third &&
            first != fourth &&
            second != third &&
            second != fourth &&
            third != fourth {
            orders.push([first, second, third, fourth])
          }
        }
      }
    }
  }
  assert_eq(orders.length(), 24)
  let actions = [
    @rollout.ReplaceAsset("a.js"),
    @rollout.ReplaceAsset("b.js"),
    @rollout.SwitchPage("first.html"),
    @rollout.SwitchPage("second.html"),
  ]
  for mask in 0..<256 {
    let pages : Array[@rollout.Page] = []
    for page in 0..<2 {
      let before = Map([])
      let after = Map([])
      for asset, name in ["a.js", "b.js"] {
        before[name] = (mask & (1 << (page * 4 + asset))) == 0
        after[name] = (mask & (1 << (page * 4 + asset + 2))) == 0
      }
      pages.push({
        path: if page == 0 {
          "first.html"
        } else {
          "second.html"
        },
        before,
        after,
      })
    }
    let mut feasible = false
    for order in orders {
      if accepts_every_state(pages, order) {
        feasible = true
      }
    }
    let result = @rollout.plan(
      pages,
      Map([("a.js", @rollout.Replace), ("b.js", @rollout.Replace)]),
    )
    assert_eq(
      result.cycle.is_empty(),
      feasible,
      msg="compatibility mask \{mask}",
    )
    if feasible {
      let order = []
      for wave in result.waves {
        for action in wave {
          order.push(
            match action {
              @rollout.ReplaceAsset("a.js") => 0
              @rollout.ReplaceAsset(_) => 1
              @rollout.SwitchPage("first.html") => 2
              @rollout.SwitchPage(_) => 3
              @rollout.PublishAsset(_) => -1
            },
          )
        }
      }
      assert_eq(order.length(), 4)
      assert_true(accepts_every_state(pages, order))
      // Independently evaluate actual intermediate page/asset combinations
      // after every possible next step of every reachable prefix.
      for order in orders {
        let replay = @rollout.begin_replay(result).unwrap()
        let prefix = []
        for next in order {
          let ready = replay.ready()
          for id, action in actions {
            let previously_applied = prefix.contains(id)
            prefix.push(id)
            let safe = !previously_applied && accepts_every_state(pages, prefix)
            ignore(prefix.pop())
            assert_eq(
              ready.contains(action),
              safe,
              msg="mask \{mask}, next \{id}",
            )
          }
          prefix.push(next)
          let accepted = replay.apply(actions[next]) is Ok(_)
          assert_eq(accepted, accepts_every_state(pages, prefix))
          if !accepted {
            assert_eq(replay.ready(), ready)
            break
          }
          assert_eq(replay.completed(), prefix.length())
        }
        assert_eq(replay.is_complete(), accepts_every_state(pages, order))
      }
    } else {
      assert_eq(
        @rollout.begin_replay(result).unwrap_err(),
        @rollout.CyclicPlan(result.cycle),
      )
      for index in 0..<(result.cycle.length() - 1) {
        assert_true(
          result.constraints.contains(
            (result.cycle[index], result.cycle[index + 1]),
          ),
        )
      }
      assert_eq(result.cycle[0], result.cycle[result.cycle.length() - 1])
    }
  }
}
