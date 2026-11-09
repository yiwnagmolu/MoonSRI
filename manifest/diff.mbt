///|
pub(all) enum Change {
  Added(String, String)
  Removed(String, String)
  Changed(String, String, String)
}

///|
/// Compare stored metadata strings in path order.
pub fn diff(
  before : Map[String, String],
  after : Map[String, String],
) -> Array[Change] {
  let paths : Array[String] = []
  for path, _ in before {
    paths.push(path)
  }
  for path, _ in after {
    if !before.contains(path) {
      paths.push(path)
    }
  }
  paths.sort_by((left, right) => left.lexical_compare(right))
  let changes = []
  for path in paths {
    match (before.get(path), after.get(path)) {
      (None, Some(value)) => changes.push(Added(path, value))
      (Some(value), None) => changes.push(Removed(path, value))
      (Some(old), Some(current)) if old != current =>
        changes.push(Changed(path, old, current))
      _ => ()
    }
  }
  changes
}
