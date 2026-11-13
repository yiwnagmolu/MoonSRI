///|
fn run_diff_html(args : ArrayView[String]) -> Int32 {
  let mut before_root = None
  let mut after_root = None
  let mut json_output = false
  let mut index = 0
  while index < args.length() {
    match args[index] {
      "--before-root" if before_root is None && index + 1 < args.length() => {
        guard parse_root_prefix(args[index + 1]) is Some(root) else { return 2 }
        before_root = Some(root)
        index += 2
      }
      "--after-root" if after_root is None && index + 1 < args.length() => {
        guard parse_root_prefix(args[index + 1]) is Some(root) else { return 2 }
        after_root = Some(root)
        index += 2
      }
      "--json" if !json_output => {
        json_output = true
        index += 1
      }
      "--" => {
        index += 1
        break
      }
      option if option.has_prefix("--") => {
        usage()
        return 2
      }
      _ => break
    }
  }
  guard before_root is Some(before) &&
    after_root is Some(after) &&
    index < args.length() else {
    usage()
    return 2
  }
  let reports : Array[Json] = []
  let mut code = 0
  for page in args[index:] {
    let (page_code, report) = diff_html_page(before, after, page, json_output)
    if page_code > code {
      code = page_code
    }
    if report is Some(report) {
      reports.push(report)
    }
  }
  if json_output {
    println(Json::array(reports).stringify(indent=2))
  }
  code
}

///|
fn build_diff_plan(
  prefix : String,
  page : String,
  source : String,
) -> Result[Array[PlanResource], String] {
  let (directory, doc) = match parse_audit_page(page, source) {
    Ok(input) => input
    Err(reason) => return Err(reason)
  }
  let plan : Array[PlanResource] = []
  for reference in doc.references {
    let url = reference.url
    let (path, suffix) = match resolve_audit_path(directory, url) {
      Local(path) => {
        let (_, suffix) = audit_url_parts(url.trim(chars=" \t\n\r\u{000c}"))
        (Some(path), suffix.to_owned())
      }
      External => (None, "")
      Directory(_) | SameDocument | Invalid => {
        eprintln(
          "Unsupported resource URL in " +
          Json::string(prefix + page).stringify() +
          ": " +
          Json::string(url).stringify(),
        )
        return Err("invalid_url")
      }
    }
    let integrity = reference.integrity.map(value => {
      @sri.canonical_metadata(value).unwrap_or(value)
    })
    plan.push({
      kind: audit_kind(reference.kind),
      url,
      path,
      suffix,
      integrity,
    })
  }
  Ok(plan)
}

///|
fn diff_html_page(
  before_root : String,
  after_root : String,
  page : String,
  json_output : Bool,
) -> (Int32, Json?) {
  let before_source = read_audit_source(before_root, page)
  let before = match before_source {
    Ok(source) => build_diff_plan(before_root, page, source)
    Err(reason) => Err(reason)
  }
  let after = match read_audit_source(after_root, page) {
    Ok(source) =>
      if before is Ok(_) && before_source is Ok(original) && original == source {
        before
      } else {
        build_diff_plan(after_root, page, source)
      }
    Err(reason) => Err(reason)
  }
  guard before is Ok(before_plan) && after is Ok(after_plan) else {
    if !json_output {
      return (2, None)
    }
    let report = Map([
      ("page", Json::string(page)),
      ("status", Json::string("error")),
    ])
    if before is Err(reason) {
      report["before_error"] = Json::string(reason)
    }
    if after is Err(reason) {
      report["after_error"] = Json::string(reason)
    }
    return (2, Some(Json::object(report)))
  }
  let changes = diff_plan(before_plan, after_plan)
  let (code, status) = if changes.has_changes() {
    (1, "changed")
  } else {
    (0, "unchanged")
  }
  if json_output {
    let report = Map([
      ("page", Json::string(page)),
      ("status", Json::string(status)),
      (
        "added",
        Json::array(
          changes.added.map(index => plan_entry(after_plan[index], index)),
        ),
      ),
      (
        "removed",
        Json::array(
          changes.removed.map(index => plan_entry(before_plan[index], index)),
        ),
      ),
      (
        "integrity_changed",
        Json::array(
          changes.integrity_changed.map(pair => {
            let (old_index, new_index) = pair
            Json::object(
              Map([
                ("before", plan_entry(before_plan[old_index], old_index)),
                ("after", plan_entry(after_plan[new_index], new_index)),
              ]),
            )
          }),
        ),
      ),
      ("order_changed", Json::boolean(changes.order_changed)),
    ])
    if changes.order_changed {
      report["before_order"] = Json::array(
        before_plan.mapi((index, item) => plan_entry(item, index)),
      )
      report["after_order"] = Json::array(
        after_plan.mapi((index, item) => plan_entry(item, index)),
      )
    }
    (code, Some(Json::object(report)))
  } else {
    println(status + ": " + Json::string(page).stringify())
    for index in changes.removed {
      println("  removed: " + plan_entry(before_plan[index], index).stringify())
    }
    for index in changes.added {
      println("  added: " + plan_entry(after_plan[index], index).stringify())
    }
    for pair in changes.integrity_changed {
      let (old_index, new_index) = pair
      println(
        "  integrity_changed: " +
        plan_entry(before_plan[old_index], old_index).stringify() +
        " -> " +
        plan_entry(after_plan[new_index], new_index).stringify(),
      )
    }
    if changes.order_changed {
      println("  order_changed")
      println("  before: " + plan_order(before_plan))
      println("  after:  " + plan_order(after_plan))
    }
    (code, None)
  }
}

///|
fn plan_order(plan : Array[PlanResource]) -> String {
  plan
  .map(item => item.kind + " " + Json::string(item.url).stringify())
  .join(", ")
}

///|
fn plan_entry(item : PlanResource, index : Int32) -> Json {
  let entry = Map([
    ("position", Json::number((index + 1).to_double())),
    ("kind", Json::string(item.kind)),
    ("url", Json::string(item.url)),
    ("integrity", item.integrity.map(Json::string).unwrap_or(Json::null())),
  ])
  if item.path is Some(path) {
    entry["path"] = Json::string(path)
  }
  Json::object(entry)
}
