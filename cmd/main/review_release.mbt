///|
fn run_review_release(args : ArrayView[String]) -> Int32 {
  guard parse_release_args(args) is Some((before, after, json_output, pages)) else {
    return 2
  }
  let unique : Set[String] = Set([])
  for page in pages {
    if unique.contains(page) {
      eprintln("Duplicate release page: " + Json::string(page).stringify())
      return 2
    }
    unique.add(page)
  }
  let (page_inputs, asset_inputs) = match
    collect_release_inputs(before, after, pages) {
    Ok(input) => input
    Err(reason) => {
      eprintln(reason)
      return 2
    }
  }
  let plan = @rollout.plan(page_inputs, asset_inputs)
  let blocked = !plan.cycle.is_empty()
  let status = if blocked { "blocked" } else { "safe" }
  if json_output {
    let report = Json::object(
      Map([
        ("status", Json::string(status)),
        (
          "waves",
          Json::array(
            plan.waves.map(wave => Json::array(wave.map(release_action_json))),
          ),
        ),
        (
          "constraints",
          Json::array(
            plan.constraints.map(edge => {
              let (first, then) = edge
              Json::object(
                Map([
                  ("first", release_action_json(first)),
                  ("then", release_action_json(then)),
                ]),
              )
            }),
          ),
        ),
        ("cycle", Json::array(plan.cycle.map(release_action_json))),
      ]),
    )
    println(report.stringify(indent=2))
  } else {
    println(status)
    if blocked {
      println("  cycle: " + plan.cycle.map(release_action_text).join(" -> "))
    } else {
      for index, wave in plan.waves {
        println("  wave " + (index + 1).to_string())
        for action in wave {
          println("    " + release_action_text(action))
        }
      }
    }
  }
  if blocked {
    1
  } else {
    0
  }
}

///|
fn release_action_parts(action : @rollout.Action) -> (String, String) {
  match action {
    @rollout.PublishAsset(path) => ("publish_asset", path)
    @rollout.ReplaceAsset(path) => ("replace_asset", path)
    @rollout.SwitchPage(path) => ("switch_page", path)
  }
}

///|
fn release_action_json(action : @rollout.Action) -> Json {
  let (kind, path) = release_action_parts(action)
  Json::object(
    Map([("kind", Json::string(kind)), ("path", Json::string(path))]),
  )
}

///|
fn release_action_text(action : @rollout.Action) -> String {
  let (kind, path) = release_action_parts(action)
  kind + " " + Json::string(path).stringify()
}
