///|
pub(all) enum Change {
  Added(String, String)
  Removed(String, String)
  Changed(String, String, String)
}

///|
fn Change::path(self : Change) -> String {
  match self {
    Added(path, _) | Removed(path, _) | Changed(path, _, _) => path
  }
}

///|
/// Compare stored metadata strings in path order.
pub fn diff(
  before : Map[String, String],
  after : Map[String, String],
) -> Array[Change] {
  let changes : Array[Change] = []
  for path, old in before {
    match after.get(path) {
      None => changes.push(Removed(path, old))
      Some(current) if old != current =>
        changes.push(Changed(path, old, current))
      _ => ()
    }
  }
  for path, current in after {
    if !before.contains(path) {
      changes.push(Added(path, current))
    }
  }
  changes.sort_by((left, right) => left.path().lexical_compare(right.path()))
  changes
}
