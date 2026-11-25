///|
/// Render every release action and constraint as a graph in the requested
/// format. Node ids follow the planner's canonical order (sorted assets, then
/// sorted pages), so repeated runs produce byte-identical output. Actions
/// outside every wave are the unscheduled remainder of a blocked plan.
fn render_release_graph(
  pages : Array[@rollout.Page],
  assets : Map[String, @rollout.AssetChange],
  plan : @rollout.Plan,
  format : String,
  describe : (@rollout.Action) -> (String, String),
) -> String? {
  let names = assets.keys().to_array()
  names.sort_by((left, right) => left.lexical_compare(right))
  let page_paths = pages.map(page => page.path)
  page_paths.sort_by((left, right) => left.lexical_compare(right))
  let asset_ids : Map[String, Int32] = Map([])
  let labels : Array[String] = []
  for name in names {
    let action = match assets[name] {
      @rollout.Publish => @rollout.PublishAsset(name)
      @rollout.Replace => @rollout.ReplaceAsset(name)
    }
    asset_ids[name] = labels.length()
    labels.push(action_label(describe(action)))
  }
  let page_ids : Map[String, Int32] = Map([])
  for path in page_paths {
    page_ids[path] = labels.length()
    labels.push(action_label(describe(@rollout.SwitchPage(path))))
  }
  fn node_of(action : @rollout.Action) -> Int32? {
    match action {
      @rollout.PublishAsset(path) | @rollout.ReplaceAsset(path) =>
        asset_ids.get(path)
      @rollout.SwitchPage(path) => page_ids.get(path)
    }
  }
  let wave_of = Array::make(labels.length(), -1)
  for wave, actions in plan.waves {
    for action in actions {
      if node_of(action) is Some(node) {
        wave_of[node] = wave
      }
    }
  }
  let in_cycle = Array::make(labels.length(), false)
  for action in plan.cycle {
    if node_of(action) is Some(node) {
      in_cycle[node] = true
    }
  }
  let edges : Array[(Int32, Int32)] = []
  for _, pair in plan.constraints {
    let (first, then) = pair
    guard node_of(first) is Some(source) && node_of(then) is Some(target) else {
      return None
    }
    edges.push((source, target))
  }
  match format {
    "mermaid" => Some(render_mermaid(labels, wave_of, in_cycle, edges))
    "dot" => Some(render_dot(labels, wave_of, in_cycle, edges))
    _ => None
  }
}

///|
fn action_label(parts : (String, String)) -> String {
  let (kind, path) = parts
  kind + " " + path
}

///|
fn render_mermaid(
  labels : Array[String],
  wave_of : Array[Int32],
  in_cycle : Array[Bool],
  edges : Array[(Int32, Int32)],
) -> String {
  let output = StringBuilder()
  output.write_string("flowchart LR\n")
  for node, label in labels {
    output.write_string(
      "  n" + node.to_string() + "[\"" + escape_mermaid(label) + "\"]\n",
    )
  }
  for wave, actions in plan_waves(wave_of) {
    output.write_string("  subgraph wave" + (wave + 1).to_string() + "\n")
    for node in actions {
      output.write_string("    n" + node.to_string() + "\n")
    }
    output.write_string("  end\n")
  }
  for pair in edges {
    let (source, target) = pair
    output.write_string(
      "  n" + source.to_string() + " --> n" + target.to_string() + "\n",
    )
  }
  for node, blocked in in_cycle {
    if blocked {
      output.write_string("  style n" + node.to_string() + " fill:#ffcccc\n")
    }
  }
  output.to_string()
}

///|
fn render_dot(
  labels : Array[String],
  wave_of : Array[Int32],
  in_cycle : Array[Bool],
  edges : Array[(Int32, Int32)],
) -> String {
  let output = StringBuilder()
  output.write_string("digraph moonsri {\n  rankdir=LR;\n")
  for node, label in labels {
    output.write_string(
      "  n" +
      node.to_string() +
      " [label=\"" +
      escape_dot(label) +
      "\"" +
      (if in_cycle[node] { ", color=red" } else { "" }) +
      "];\n",
    )
  }
  for wave, actions in plan_waves(wave_of) {
    output.write_string(
      "  subgraph cluster_wave" + (wave + 1).to_string() + " {\n",
    )
    output.write_string("    label=\"wave " + (wave + 1).to_string() + "\";\n")
    for node in actions {
      output.write_string("    n" + node.to_string() + ";\n")
    }
    output.write_string("  }\n")
  }
  for pair in edges {
    let (source, target) = pair
    output.write_string(
      "  n" + source.to_string() + " -> n" + target.to_string() + ";\n",
    )
  }
  output.write_string("}\n")
  output.to_string()
}

///|
fn plan_waves(wave_of : Array[Int32]) -> Array[Array[Int32]] {
  let mut count = 0
  for wave in wave_of {
    if wave >= count {
      count = wave + 1
    }
  }
  let waves : Array[Array[Int32]] = Array::makei(count, _ => [])
  for node, wave in wave_of {
    if wave >= 0 {
      waves[wave].push(node)
    }
  }
  waves
}

///|
fn escape_mermaid(label : String) -> String {
  let output = StringBuilder()
  for ch in label {
    match ch {
      '"' => output.write_string("&quot;")
      '<' => output.write_string("&lt;")
      '>' => output.write_string("&gt;")
      _ => output.write_char(ch)
    }
  }
  output.to_string()
}

///|
fn escape_dot(label : String) -> String {
  let output = StringBuilder()
  for ch in label {
    match ch {
      '"' => output.write_string("\\\"")
      '\\' => output.write_string("\\\\")
      _ => output.write_char(ch)
    }
  }
  output.to_string()
}
