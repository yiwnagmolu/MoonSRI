///|
test "resume after an early action and cross wave boundaries" {
  let first = @rollout.PublishAsset("a.js")
  let second = @rollout.PublishAsset("b.js")
  let other = @rollout.SwitchPage("other.html")
  let switch = @rollout.SwitchPage("首页.html")
  let replay = @rollout.begin_replay({
    waves: [[first, second, other], [switch]],
    cycle: [],
    constraints: [(second, switch), (first, switch)],
  }).unwrap()
  assert_eq(replay.ready(), [first, second, other])
  assert_eq(replay.total(), 4)
  assert_eq(replay.completed(), 0)
  assert_false(replay.is_complete())
  assert_eq(
    replay.apply(switch),
    Err(@rollout.UnmetPrerequisites(switch, [first, second])),
  )
  let wrong_kind = @rollout.ReplaceAsset("a.js")
  assert_eq(replay.apply(wrong_kind), Err(@rollout.UnknownAction(wrong_kind)))
  replay.apply(second).unwrap()
  assert_eq(replay.apply(second), Err(@rollout.RepeatedAction(second)))
  assert_eq(
    replay.apply(switch),
    Err(@rollout.UnmetPrerequisites(switch, [first])),
  )
  assert_eq(replay.completed(), 1)
  replay.apply(first).unwrap()
  assert_eq(replay.ready(), [other, switch])
  replay.apply(switch).unwrap()
  assert_eq(replay.ready(), [other])
  replay.apply(other).unwrap()
  assert_true(replay.is_complete())
  assert_eq(replay.completed(), replay.total())
  assert_eq(replay.ready(), [])
  assert_eq(replay.apply(other), Err(@rollout.RepeatedAction(other)))
}

///|
test "empty, cyclic and malformed plans have distinct outcomes" {
  let empty = @rollout.begin_replay(@rollout.plan([], Map([]))).unwrap()
  assert_true(empty.is_complete())
  assert_eq(empty.completed(), 0)
  assert_eq(empty.ready(), [])
  let page = @rollout.SwitchPage("unrelated")
  let asset = @rollout.ReplaceAsset("app.js")
  let use_asset = @rollout.SwitchPage("index.html")
  let cycle = [asset, use_asset, asset]
  let blocked : @rollout.Plan = {
    waves: [[page]],
    cycle,
    constraints: [(asset, use_asset), (use_asset, asset)],
  }
  assert_eq(
    @rollout.begin_replay(blocked).unwrap_err(),
    @rollout.CyclicPlan(cycle),
  )
  let valid : @rollout.Plan = {
    waves: [[asset], [use_asset]],
    cycle: [],
    constraints: [(asset, use_asset)],
  }
  let invalid : Array[@rollout.Plan] = [
    { ..valid, waves: [[], [asset], [use_asset]], },
    { ..valid, waves: [[asset, asset], [use_asset]], },
    { ..valid, waves: [[asset], [asset, use_asset]], },
    { ..valid, waves: [[asset, use_asset]], },
    { ..valid, constraints: [(asset, asset)], },
    { ..valid, constraints: [(use_asset, asset)], },
    { ..valid, constraints: [(page, use_asset)], },
    { ..valid, constraints: [(asset, page)], },
    { ..valid, constraints: [(asset, use_asset), (asset, use_asset)], },
  ]
  for plan in invalid {
    assert_eq(@rollout.begin_replay(plan).unwrap_err(), @rollout.InvalidPlan)
  }
}

///|
test "replays snapshot the input graph and keep independent progress" {
  let asset = @rollout.PublishAsset("app.js")
  let page = @rollout.SwitchPage("index.html")
  let wave = [asset]
  let plan : @rollout.Plan = {
    waves: [wave, [page]],
    cycle: [],
    constraints: [(asset, page)],
  }
  let first = @rollout.begin_replay(plan).unwrap()
  let second = @rollout.begin_replay(plan).unwrap()
  wave[0] = page
  plan.constraints.clear()
  let ready = first.ready()
  ready[0] = page
  assert_eq(first.ready(), [asset])
  first.apply(asset).unwrap()
  assert_eq(first.ready(), [page])
  assert_eq(second.ready(), [asset])
  assert_eq(second.apply(page), Err(@rollout.UnmetPrerequisites(page, [asset])))
}

///|
test "wide release joins thousands of page actions without dropping dependencies" {
  let pages : Array[@rollout.Page] = Array::makei(2048, i => {
    path: "page-\{i}.html",
    before: Map([("old.js", false)]),
    after: Map([("new.js", false)]),
  })
  let release = @rollout.plan(
    pages,
    Map([("old.js", @rollout.Replace), ("new.js", @rollout.Publish)]),
  )
  let replay = @rollout.begin_replay(release).unwrap()
  let publish = @rollout.PublishAsset("new.js")
  let replace = @rollout.ReplaceAsset("old.js")
  assert_eq(replay.ready(), [publish])
  replay.apply(publish).unwrap()
  let switches = replay.ready()
  assert_eq(switches, release.waves[1])
  assert_eq(switches.length(), 2048)
  for i = switches.length() - 1; i > 0; i = i - 1 {
    replay.apply(switches[i]).unwrap()
  }
  assert_eq(replay.ready(), [switches[0]])
  assert_eq(
    replay.apply(replace),
    Err(@rollout.UnmetPrerequisites(replace, [switches[0]])),
  )
  replay.apply(switches[0]).unwrap()
  assert_eq(replay.ready(), [replace])
  replay.apply(replace).unwrap()
  assert_true(replay.is_complete())
}

///|
test "deep chains can be fully replayed and deep cycles refused" {
  let n = 1024
  let pages : Array[@rollout.Page] = []
  let assets : Map[String, @rollout.AssetChange] = Map([])
  for i in 0..<n {
    let asset = "lib-\{i}.js"
    assets[asset] = @rollout.Replace
    pages.push({
      path: "page-\{i}.html",
      before: if i + 1 < n {
        Map([("lib-\{i + 1}.js", false)])
      } else {
        Map([])
      },
      after: Map([(asset, false)]),
    })
  }
  let release = @rollout.plan(pages, assets)
  let replay = @rollout.begin_replay(release).unwrap()
  assert_eq(replay.total(), 2 * n)
  for wave in release.waves {
    assert_eq(wave.length(), 1)
    assert_eq(replay.ready(), wave)
    replay.apply(wave[0]).unwrap()
  }
  assert_true(replay.is_complete())
  pages[n - 1].before["lib-0.js"] = false
  let cyclic = @rollout.plan(pages, assets)
  assert_eq(cyclic.cycle.length(), 2 * n + 1)
  assert_eq(
    @rollout.begin_replay(cyclic).unwrap_err(),
    @rollout.CyclicPlan(cyclic.cycle),
  )
}
