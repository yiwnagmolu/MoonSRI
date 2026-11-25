///|
/// Accept the same action objects that review-release writes in its waves.
fn parse_release_order(
  source : String,
) -> Result[Array[(String, String)], String] {
  let parsed = @json.parse(source, reject_duplicate_keys=true) catch {
    error => return Err("Invalid release order JSON: " + error.to_string())
  }
  guard parsed is Array(items) else {
    return Err("Expected a JSON array of release actions")
  }
  let steps = []
  for index, item in items {
    guard item is Object(fields) &&
      fields.length() == 2 &&
      fields.get("kind") is Some(String(kind)) &&
      fields.get("path") is Some(String(path)) &&
      is_portable_relative_path(path) else {
      return Err(
        "Expected kind and portable path at release step " +
        (index + 1).to_string(),
      )
    }
    match kind {
      "publish_asset"
      | "replace_asset"
      | "publish_page"
      | "retire_page"
      | "switch_page" => steps.push((kind, path))
      _ =>
        return Err(
          "Unknown action kind at release step " +
          (index + 1).to_string() +
          ": " +
          Json::string(kind).stringify(),
        )
    }
  }
  Ok(steps)
}

///|
priv struct OrderFailure {
  action : (String, String)
  reason : String
  waiting_for : Array[@rollout.Action]
}

///|
fn check_release_order(
  plan : @rollout.Plan,
  steps : Array[(String, String)],
  describe : (@rollout.Action) -> (String, String),
  options : ReleaseArgs,
  verify_live : (String) -> LiveReport,
) -> Int32 {
  let encode = action => release_action_json(describe(action))
  let direction = if options.rollback { "rollback" } else { "forward" }
  let replay = match @rollout.begin_replay(plan) {
    Ok(replay) => replay
    Err(@rollout.CyclicPlan(cycle)) => {
      if options.json_output {
        println(
          Json::object({
            "status": Json::string("blocked"),
            "direction": Json::string(direction),
            "cycle": Json::array(cycle.map(encode)),
          }).stringify(indent=2),
        )
      } else {
        println(direction + " blocked")
        println(
          "  cycle: " +
          cycle.map(a => release_action_text(describe(a))).join(" -> "),
        )
      }
      return 1
    }
    Err(_) => {
      eprintln("Inconsistent generated release plan")
      return 2
    }
  }
  let mut failure : OrderFailure? = None
  for step in steps {
    let (kind, path) = step
    let action = match kind {
      "publish_asset" => @rollout.PublishAsset(path)
      "replace_asset" => @rollout.ReplaceAsset(path)
      _ => @rollout.SwitchPage(path)
    }
    // The graph shares one node type for page operations. A journal must
    // nevertheless name the actual operation for the selected inventories.
    if describe(action) != step {
      failure = Some({
        action: step,
        reason: "unknown_action",
        waiting_for: [],
      })
      break
    }
    match replay.apply(action) {
      Ok(_) => ()
      Err(error) => {
        let (reason, waiting_for) = match error {
          @rollout.UnknownAction(_) => ("unknown_action", [])
          @rollout.RepeatedAction(_) => ("repeated_action", [])
          @rollout.UnmetPrerequisites(_, waiting) =>
            ("unmet_prerequisites", waiting)
          _ => {
            eprintln("Inconsistent release replay state")
            return 2
          }
        }
        failure = Some({ action: step, reason, waiting_for, })
        break
      }
    }
  }
  let (order_code, status) = if failure is Some(_) {
    (1, "rejected")
  } else if replay.is_complete() {
    (0, "complete")
  } else if options.require_complete {
    (1, "incomplete")
  } else {
    (0, "partial")
  }
  let ready = replay.ready()
  let live = if failure is None && options.live_root is Some(root) {
    Some(verify_live(root))
  } else {
    None
  }
  if options.json_output {
    let report : Map[String, Json] = {
      "status": Json::string(status),
      "direction": Json::string(direction),
      "completed": Json::number(replay.completed().to_double()),
      "total": Json::number(replay.total().to_double()),
      "ready": Json::array(ready.map(encode)),
    }
    if failure is Some(problem) {
      report["failure"] = Json::object({
        "step": Json::number((replay.completed() + 1).to_double()),
        "action": release_action_json(problem.action),
        "reason": Json::string(problem.reason),
        "waiting_for": Json::array(problem.waiting_for.map(encode)),
      })
    }
    if live is Some(check) {
      report["live"] = check.to_json()
    }
    println(Json::object(report).stringify(indent=2))
  } else {
    let format = action => release_action_text(describe(action))
    println(
      direction +
      " " +
      status +
      " " +
      replay.completed().to_string() +
      "/" +
      replay.total().to_string(),
    )
    if failure is Some(problem) {
      println(
        "  step " +
        (replay.completed() + 1).to_string() +
        " " +
        problem.reason +
        ": " +
        release_action_text(problem.action),
      )
      for pending in problem.waiting_for {
        println("    waiting for " + format(pending))
      }
    }
    for next in ready {
      println("  ready " + format(next))
    }
    if live is Some(check) {
      println(
        "  live " +
        check.status() +
        " (" +
        check.checked.to_string() +
        " paths)",
      )
      for finding in check.findings {
        println(
          "    " +
          finding.status +
          " " +
          Json::string(finding.path).stringify() +
          " expected=" +
          finding.expected,
        )
      }
    }
  }
  if live is Some(check) && check.code > order_code {
    check.code
  } else {
    order_code
  }
}
