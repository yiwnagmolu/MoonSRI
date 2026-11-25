///|
fn run_review_release(args : ArrayView[String]) -> Int32 {
  guard parse_release_args(args, review=true) is Some(options) else { return 2 }
  let (before_pages, after_pages) = match options.inventories {
    Some((before, after)) => {
      guard read_release_inventory(before) is Some(before_pages) &&
        read_release_inventory(after) is Some(after_pages) else {
        return 2
      }
      (before_pages[:], after_pages[:])
    }
    None => (options.pages, options.pages)
  }
  let (start_root, end_root, start_pages, end_pages) = if options.rollback {
    (options.after, options.before, after_pages, before_pages)
  } else {
    (options.before, options.after, before_pages, after_pages)
  }
  if before_pages.is_empty() && after_pages.is_empty() {
    eprintln("At least one release page is required")
    return 2
  }
  guard unique_release_pages(before_pages, "before") is Some(old_set) &&
    unique_release_pages(after_pages, "after") is Some(new_set) else {
    return 2
  }
  let (before_set, after_set) = if options.rollback {
    (new_set, old_set)
  } else {
    (old_set, new_set)
  }
  let order = match options.order_file {
    Some(path) => {
      guard read_utf8_file(path, "release order") is Some(source) else {
        return 2
      }
      match parse_release_order(source) {
        Ok(steps) => Some(steps)
        Err(message) => {
          eprintln(message)
          return 2
        }
      }
    }
    None => None
  }
  let (page_inputs, asset_inputs, retained) = match
    collect_release_inputs(start_root, end_root, start_pages, end_pages) {
    Ok(input) => input
    Err(reason) => {
      eprintln(reason)
      return 2
    }
  }
  let plan = @rollout.plan(page_inputs, asset_inputs)
  // An absent version has no references. The graph still treats every page
  // change as one atomic action, and the inventory provides its display kind.
  let describe = action => release_action_parts(action, before_set, after_set)
  let blocked = !plan.cycle.is_empty()
  if order is Some(steps) {
    return check_release_order(plan, steps, describe, options, live_root => {
      verify_live_release(
        live_root, start_root, end_root, before_set, page_inputs, steps,
      )
    })
  }
  let status = if blocked { "blocked" } else { "safe" }
  if options.json_output {
    let encode = action => release_action_json(describe(action))
    let report = Map([
      ("status", Json::string(status)),
      (
        "waves",
        Json::array(plan.waves.map(wave => Json::array(wave.map(encode)))),
      ),
      (
        "constraints",
        Json::array(
          plan.constraints.map(edge => {
            let (first, then) = edge
            Json::object(
              Map([("first", encode(first)), ("then", encode(then))]),
            )
          }),
        ),
      ),
      ("cycle", Json::array(plan.cycle.map(encode))),
    ])
    if options.inventories is Some(_) {
      report["retained_assets"] = Json::array(retained.map(Json::string))
    }
    if options.rollback {
      report["direction"] = Json::string("rollback")
    }
    println(Json::object(report).stringify(indent=2))
  } else {
    if options.rollback {
      println("rollback")
    }
    let format = action => release_action_text(describe(action))
    println(status)
    if blocked {
      println("  cycle: " + plan.cycle.map(format).join(" -> "))
    } else {
      for index, wave in plan.waves {
        println("  wave " + (index + 1).to_string())
        for action in wave {
          println("    " + format(action))
        }
      }
    }
    if options.inventories is Some(_) {
      for path in retained {
        println("  retain_asset " + Json::string(path).stringify())
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
fn read_release_inventory(path : String) -> Array[String]? {
  guard read_utf8_file(path, "page inventory") is Some(source) else {
    return None
  }
  let pages = []
  for line in source.split("\n") {
    let page = line.strip_suffix("\r").unwrap_or(line)
    if !page.is_empty() {
      pages.push(page.to_owned())
    }
  }
  Some(pages)
}

///|
fn unique_release_pages(
  pages : ArrayView[String],
  side : String,
) -> Set[String]? {
  let unique : Set[String] = Set([])
  for page in pages {
    if unique.contains(page) {
      eprintln(
        "Duplicate " + side + " release page: " + Json::string(page).stringify(),
      )
      return None
    }
    unique.add(page)
  }
  Some(unique)
}

///|
fn release_action_parts(
  action : @rollout.Action,
  before : Set[String],
  after : Set[String],
) -> (String, String) {
  match action {
    @rollout.PublishAsset(path) => ("publish_asset", path)
    @rollout.ReplaceAsset(path) => ("replace_asset", path)
    @rollout.SwitchPage(path) =>
      if !before.contains(path) {
        ("publish_page", path)
      } else if !after.contains(path) {
        ("retire_page", path)
      } else {
        ("switch_page", path)
      }
  }
}

///|
fn release_action_json(parts : (String, String)) -> Json {
  let (kind, path) = parts
  Json::object(
    Map([("kind", Json::string(kind)), ("path", Json::string(path))]),
  )
}

///|
fn release_action_text(parts : (String, String)) -> String {
  let (kind, path) = parts
  kind + " " + Json::string(path).stringify()
}
