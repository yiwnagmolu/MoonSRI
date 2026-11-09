///|
/// An incremental SRI hasher for callers that receive a resource in chunks.
struct Hasher {
  algorithm : Algorithm
  state : @sha2.Hasher
}

///|
pub fn Hasher::new(algorithm : Algorithm) -> Hasher {
  { algorithm, state: @sha2.Hasher::new(kind=algorithm.kind()), }
}

///|
/// Append bytes in resource order.
pub fn Hasher::update(self : Hasher, data : BytesView) -> Unit {
  self.state.write(data)
}

///|
/// Return the token for bytes seen so far without changing the current state.
pub fn Hasher::metadata(self : Hasher) -> String {
  let digest = self.state.finish()
  self.algorithm.label() + "-" + @base64.encode(digest[:])
}

///|
/// Start hashing a new resource with the same algorithm.
pub fn Hasher::reset(self : Hasher) -> Unit {
  self.state.reset()
}
