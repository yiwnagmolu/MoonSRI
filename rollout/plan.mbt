///|
/// Each map lists the local assets referenced by that version of the page.
/// Its value states whether those declarations accept the opposite version's
/// asset bytes. Callers must first verify both versions against their own bytes.
pub(all) struct Page {
  path : String
  before : Map[String, Bool]
  after : Map[String, Bool]
}

///|
pub(all) enum AssetChange {
  Publish
  Replace
}

///|
#derive(Eq, Debug)
pub(all) enum Action {
  PublishAsset(String)
  ReplaceAsset(String)
  SwitchPage(String)
}

///|
#derive(Eq, Debug)
pub(all) struct Plan {
  waves : Array[Array[Action]]
  cycle : Array[Action]
  constraints : Array[(Action, Action)]
}

///|
pub extend Action with Eq::{equal, not_equal}

///|
pub extend Action with @debug.Debug::{to_repr}

///|
pub extend Plan with Eq::{equal, not_equal}

///|
pub extend Plan with @debug.Debug::{to_repr}

///|
/// Plan independent actions in deterministic waves.
///
/// Every input page gets a switch action. Assets omitted from `assets` are kept
/// unchanged. A nonempty cycle repeats its first action at the end and means
/// that the returned waves are only a schedulable prefix, not a complete plan.
pub fn plan(pages : Array[Page], assets : Map[String, AssetChange]) -> Plan {
  let names : Array[String] = []
  for name, _ in assets {
    names.push(name)
  }
  names.sort_by((left, right) => left.lexical_compare(right))
  let ordered_pages = pages.copy()
  ordered_pages.sort_by((left, right) => left.path.lexical_compare(right.path))
  let actions : Array[Action] = []
  let indices : Map[String, Int32] = Map([])
  for name in names {
    indices[name] = actions.length()
    actions.push(
      match assets[name] {
        Publish => PublishAsset(name)
        Replace => ReplaceAsset(name)
      },
    )
  }
  for page in ordered_pages {
    actions.push(SwitchPage(page.path))
  }
  let edges : Array[Array[Int32]] = Array::makei(actions.length(), _ => [])
  let before_users : Array[Array[Int32]] = Array::makei(names.length(), _ => [])
  let incoming = Array::make(actions.length(), 0)
  for index, page in ordered_pages {
    let node = names.length() + index
    for asset, compatible in page.before {
      if !compatible && indices.get(asset) is Some(resource) {
        before_users[resource].push(node)
      }
    }
    for asset, compatible in page.after {
      if !compatible && indices.get(asset) is Some(resource) {
        edges[resource].push(node)
        incoming[node] += 1
      }
    }
  }
  // Iterating sorted asset nodes makes each page's outgoing edges ordered
  // without sorting every page's references.
  for resource, users in before_users {
    for node in users {
      edges[node].push(resource)
      incoming[resource] += 1
    }
  }
  let constraints = []
  let mut ready = []
  for node, successors in edges {
    if incoming[node] == 0 {
      ready.push(node)
    }
    for successor in successors {
      constraints.push((actions[node], actions[successor]))
    }
  }
  let waves = []
  let mut scheduled = 0
  while !ready.is_empty() {
    waves.push(ready.map(node => actions[node]))
    scheduled += ready.length()
    let next = []
    for node in ready {
      for successor in edges[node] {
        incoming[successor] -= 1
        if incoming[successor] == 0 {
          next.push(successor)
        }
      }
    }
    next.sort()
    ready = next
  }
  let cycle = if scheduled == actions.length() {
    []
  } else {
    find_cycle(edges, incoming).map(node => actions[node])
  }
  { waves, cycle, constraints, }
}

///|
// An iterative DFS keeps deep dependency chains off the host call stack.
fn find_cycle(
  edges : Array[Array[Int32]],
  incoming : Array[Int32],
) -> Array[Int32] {
  let colors = Array::make(edges.length(), 0)
  let parents = Array::make(edges.length(), -1)
  let stack : Array[(Int32, Int32)] = []
  for start = 0; start < edges.length(); start = start + 1 {
    if incoming[start] == 0 || colors[start] != 0 {
      continue
    }
    colors[start] = 1
    stack.push((start, 0))
    while stack.pop() is Some((node, edge)) {
      if edge == edges[node].length() {
        colors[node] = 2
        continue
      }
      stack.push((node, edge + 1))
      let successor = edges[node][edge]
      if incoming[successor] == 0 {
        continue
      }
      if colors[successor] == 1 {
        let cycle = [node]
        let mut ancestor = node
        while ancestor != successor {
          ancestor = parents[ancestor]
          cycle.push(ancestor)
        }
        cycle.rev_in_place()
        cycle.push(successor)
        return cycle
      }
      if colors[successor] == 0 {
        parents[successor] = node
        colors[successor] = 1
        stack.push((successor, 0))
      }
    }
  }
  []
}
