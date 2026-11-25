///|
// Build independent 32-action chains from real rollout Page records. The log
// finishes each chain before starting the next, crossing planner wave boundaries.
// Only opening a fresh replay and consuming its complete log are timed.
test "replay 32-wave releases" (b : @bench.T) {
  for chains in [32, 128, 512] {
    let pages : Array[@rollout.Page] = []
    let assets : Map[String, @rollout.AssetChange] = Map([])
    let order = []
    for group in 0..<chains {
      for stage in 0..<16 {
        let asset = "lib-\{group}-\{stage}.js"
        let page = "page-\{group}-\{stage}.html"
        assets[asset] = @rollout.Replace
        let before = Map([])
        if stage < 15 {
          before["lib-\{group}-\{stage + 1}.js"] = false
        }
        pages.push({ path: page, before, after: Map([(asset, false)]), })
        order.push(@rollout.ReplaceAsset(asset))
        order.push(@rollout.SwitchPage(page))
      }
    }
    let release = @rollout.plan(pages, assets)
    assert_eq(release.waves.length(), 32)
    assert_eq(release.constraints.length(), chains * 31)
    b.bench(name="\{chains * 32} actions / \{chains * 31} constraints", fn() {
      let replay = @rollout.begin_replay(release).unwrap()
      for action in order {
        replay.apply(action).unwrap()
      }
      guard! replay.is_complete()
      b.keep(replay.completed())
    })
  }
}
