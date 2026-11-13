///|
priv struct PlanResource {
  kind : String
  url : String
  path : String?
  suffix : String
  integrity : String?
}

///|
priv struct PlanDiff {
  added : Array[Int32]
  removed : Array[Int32]
  integrity_changed : Array[(Int32, Int32)]
  order_changed : Bool
}

///|
fn PlanDiff::has_changes(self : PlanDiff) -> Bool {
  self.order_changed ||
  !self.added.is_empty() ||
  !self.removed.is_empty() ||
  !self.integrity_changed.is_empty()
}

///|
fn PlanResource::key(self : PlanResource) -> (String, String?, String) {
  let tail = if self.path is Some(_) {
    self.suffix
  } else {
    self.url.trim(chars=" \t\n\r\u{000c}").to_owned()
  }
  (self.kind, self.path, tail)
}

///|
fn diff_plan(
  before : Array[PlanResource],
  after : Array[PlanResource],
) -> PlanDiff {
  if physical_equal(before, after) {
    return {
      added: [],
      removed: [],
      integrity_changed: [],
      order_changed: false,
    }
  }
  let positions : Map[(String, String?, String), Array[Int32]] = Map([])
  for index, resource in before {
    let key = resource.key()
    match positions.get(key) {
      Some(indices) => indices.push(index)
      None => positions[key] = [index]
    }
  }
  let occurrences : Map[(String, String?, String), Int32] = Map([])
  let retained = Array::make(before.length(), false)
  let added = []
  let removed = []
  let integrity_changed = []
  let mut order_changed = false
  let mut previous = -1
  for index, resource in after {
    let key = resource.key()
    let occurrence = occurrences.get(key).unwrap_or(0)
    guard positions.get(key) is Some(indices) &&
      indices.get(occurrence) is Some(original) else {
      added.push(index)
      continue
    }
    occurrences[key] = occurrence + 1
    retained[original] = true
    if before[original].integrity != resource.integrity {
      integrity_changed.push((original, index))
    }
    if original < previous {
      order_changed = true
    }
    previous = original
  }
  for index, keep in retained {
    if !keep {
      removed.push(index)
    }
  }
  { added, removed, integrity_changed, order_changed, }
}
