///|
/// A refused step leaves the replay at the last accepted prefix.
#derive(Eq, Debug)
pub(all) enum ReplayError {
  CyclicPlan(Array[Action])
  InvalidPlan
  UnknownAction(Action)
  RepeatedAction(Action)
  UnmetPrerequisites(Action, Array[Action])
}

///|
pub extend ReplayError with Eq::{equal, not_equal}

///|
pub extend ReplayError with @debug.Debug::{to_repr}

///|
// Edge indices link each node's neighbors in flat arrays. Wide or sparse
// releases incur no per-node allocation for empty or one-element lists.
priv struct Adjacency {
  first : FixedArray[Int32]
  next : FixedArray[Int32]
  neighbor : FixedArray[Int32]
}

///|
fn Adjacency::new(nodes : Int32, edges : Int32) -> Adjacency {
  {
    first: FixedArray::make(nodes, -1),
    next: FixedArray::make(edges, -1),
    neighbor: FixedArray::make(edges, 0),
  }
}

///|
fn Adjacency::prepend(
  self : Adjacency,
  node : Int32,
  neighbor : Int32,
  edge : Int32,
) -> Unit {
  self.next[edge] = self.first[node]
  self.neighbor[edge] = neighbor
  self.first[node] = edge
}

///|
/// Incremental validation of atomic actions against a release plan's direct
/// constraints. State belongs to a single replay and does not modify the plan.
pub struct Replay {
  priv actions : Array[Action]
  priv indices : Map[Action, Int32]
  priv successors : Adjacency
  priv predecessors : Adjacency
  // Number of outstanding predecessors. An applied action is marked -1.
  priv outstanding : FixedArray[Int32]
  priv available : Set[Int32]
  priv mut applied : Int32
}

///|
/// Open a replay for an acyclic plan. A plan with a cycle is rejected even
/// if it contains executable waves before the cycle. For manually constructed
/// plans, every action must occur once, waves must be nonempty, and every
/// constraint must be unique and point from an earlier wave to a later wave.
pub fn begin_replay(plan : Plan) -> Result[Replay, ReplayError] {
  if !plan.cycle.is_empty() {
    return Err(CyclicPlan(plan.cycle.copy()))
  }
  let total = plan.waves.fold(init=0, (n, wave) => n + wave.length())
  let actions = Array(capacity=total)
  let wave_starts = Array(capacity=total)
  let indices : Map[Action, Int32] = Map([], capacity=total)
  for wave in plan.waves {
    let start = actions.length()
    if wave.is_empty() {
      return Err(InvalidPlan)
    }
    for action in wave {
      indices[action] = actions.length()
      actions.push(action)
      wave_starts.push(start)
    }
  }
  if indices.length() != actions.length() {
    return Err(InvalidPlan)
  }
  let successors = Adjacency::new(total, plan.constraints.length())
  let predecessors = Adjacency::new(total, plan.constraints.length())
  let outstanding = FixedArray::make(total, 0)
  for edge, pair in plan.constraints {
    let (first, then) = pair
    guard indices.get(first) is Some(source) &&
      indices.get(then) is Some(target) &&
      source < wave_starts[target] else {
      return Err(InvalidPlan)
    }
    successors.prepend(source, target, edge)
    outstanding[target] += 1
  }
  // Prepending sources in reverse wave order yields ordered blocker lists.
  for source = total - 1; source >= 0; source = source - 1 {
    for edge = successors.first[source]; edge >= 0; edge = successors.next[edge] {
      let target = successors.neighbor[edge]
      let head = predecessors.first[target]
      if head >= 0 && predecessors.neighbor[head] == source {
        return Err(InvalidPlan)
      }
      predecessors.prepend(target, source, edge)
    }
  }
  let available : Set[Int32] = Set([])
  for node, count in outstanding {
    if count == 0 {
      available.add(node)
    }
  }
  Ok({
    actions,
    indices,
    successors,
    predecessors,
    outstanding,
    available,
    applied: 0,
  })
}

///|
/// Record one observed action. Only its direct successors need updating.
/// On an ordering failure, returns all unfinished immediate predecessors in
/// the original plan's wave and action order.
pub fn Replay::apply(
  self : Replay,
  action : Action,
) -> Result[Unit, ReplayError] {
  guard self.indices.get(action) is Some(node) else {
    return Err(UnknownAction(action))
  }
  if self.outstanding[node] < 0 {
    return Err(RepeatedAction(action))
  }
  if self.outstanding[node] > 0 {
    let blockers = []
    let incoming = self.predecessors
    for edge = incoming.first[node]; edge >= 0; edge = incoming.next[edge] {
      let predecessor = incoming.neighbor[edge]
      if self.outstanding[predecessor] >= 0 {
        blockers.push(self.actions[predecessor])
      }
    }
    return Err(UnmetPrerequisites(action, blockers))
  }
  self.outstanding[node] = -1
  self.applied += 1
  self.available.remove(node)
  let outgoing = self.successors
  for edge = outgoing.first[node]; edge >= 0; edge = outgoing.next[edge] {
    let successor = outgoing.neighbor[edge]
    self.outstanding[successor] -= 1
    if self.outstanding[successor] == 0 {
      self.available.add(successor)
    }
  }
  Ok(())
}

///|
/// All actions that can run next, returned in original plan order. The caller
/// may freely reorder these actions. The returned array is a detached snapshot.
pub fn Replay::ready(self : Replay) -> Array[Action] {
  let nodes = self.available.to_array()
  nodes.sort()
  nodes.map(node => self.actions[node])
}

///|
/// Every action that has not been applied yet, in original plan order. Unlike
/// `ready`, these actions may still be waiting on their prerequisites.
pub fn Replay::pending(self : Replay) -> Array[Action] {
  let remaining = self.total() - self.completed()
  let result = Array(capacity=remaining)
  for node, state in self.outstanding {
    if state >= 0 {
      result.push(self.actions[node])
    }
  }
  result
}

///|
pub fn Replay::completed(self : Replay) -> Int32 {
  self.applied
}

///|
pub fn Replay::total(self : Replay) -> Int32 {
  self.actions.length()
}

///|
pub fn Replay::is_complete(self : Replay) -> Bool {
  self.completed() == self.total()
}
