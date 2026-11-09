///|
/// SRI 1.0 algorithms supported by this library.
pub(all) enum Algorithm {
  Sha256
  Sha384
  Sha512
}

///|
/// A token with a recognized SRI hash algorithm.
pub(all) struct Metadata {
  algorithm : Algorithm
  digest : String
}

///| NoSupportedMetadata is deliberately distinct from a digest mismatch.

///|
/// An offline checker should not silently accept an empty or unknown-only list.
pub(all) enum Verdict {
  Match
  Mismatch
  NoSupportedMetadata
}

///|
fn Algorithm::label(self : Algorithm) -> String {
  match self {
    Sha256 => "sha256"
    Sha384 => "sha384"
    Sha512 => "sha512"
  }
}

///|
fn Algorithm::strength(self : Algorithm) -> Int32 {
  match self {
    Sha256 => 1
    Sha384 => 2
    Sha512 => 3
  }
}

///|
/// Generate one SRI metadata token for exact resource bytes.
pub fn generate(data : BytesView, algorithm : Algorithm) -> String {
  algorithm.label() + "-" + encoded_digest(data, algorithm)
}

///|
fn encoded_digest(data : BytesView, algorithm : Algorithm) -> String {
  let digest = @sha2.hash(data, kind=algorithm.kind())
  @base64.encode(digest[:])
}

///|
fn Algorithm::kind(self : Algorithm) -> @sha2.Kind {
  match self {
    Sha256 => @sha2.Sha256
    Sha384 => @sha2.Sha384
    Sha512 => @sha2.Sha512
  }
}

///|
fn is_metadata_space(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' || ch == '\u{000c}'
}

///|
fn parse_token(token : String) -> Metadata? {
  // SRI reads the expression before '?' and the digest in its second field.
  let expression = match token.split_once("?") {
    Some((expression, _)) => expression
    None => token[:]
  }
  let (label, tail) = match expression.split_once("-") {
    Some(parts) => parts
    None => (expression, ""[:])
  }
  let algorithm = if label.compare_ignore_ascii_case("sha256") == 0 {
    Sha256
  } else if label.compare_ignore_ascii_case("sha384") == 0 {
    Sha384
  } else if label.compare_ignore_ascii_case("sha512") == 0 {
    Sha512
  } else {
    return None
  }
  let digest = match tail.split_once("-") {
    Some((digest, _)) => digest.to_owned()
    None => tail.to_owned()
  }
  Some({ algorithm, digest, })
}

///|
/// Parse SRI tokens using the algorithm in SRI 1.0, ignoring unknown algorithms.
pub fn parse_metadata(input : String) -> Array[Metadata] {
  let result : Array[Metadata] = []
  let token = StringBuilder()
  for ch in input {
    if is_metadata_space(ch) {
      if !token.is_empty() {
        match parse_token(token.to_string()) {
          Some(item) => result.push(item)
          None => ()
        }
        token.reset()
      }
    } else {
      token.write_char(ch)
    }
  }
  if !token.is_empty() {
    match parse_token(token.to_string()) {
      Some(item) => result.push(item)
      None => ()
    }
  }
  result
}

///| Compare resource bytes with only the strongest supported hash family.

///|
/// Multiple digests of that strength are alternatives, as in SRI 1.0.
pub fn verify_bytes(data : BytesView, input : String) -> Verdict {
  let items = parse_metadata(input)
  guard strongest_algorithm(items) is Some(strongest) else {
    return NoSupportedMetadata
  }
  verify_strongest(data, items, strongest)
}

///|
/// Verify with a minimum algorithm strength. Err contains the strongest
/// advertised algorithm when it falls below the minimum.
pub fn verify_bytes_at_least(
  data : BytesView,
  input : String,
  minimum : Algorithm,
) -> Result[Verdict, Algorithm] {
  let items = parse_metadata(input)
  guard strongest_algorithm(items) is Some(strongest) else {
    return Ok(NoSupportedMetadata)
  }
  if strongest.strength() < minimum.strength() {
    return Err(strongest)
  }
  Ok(verify_strongest(data, items, strongest))
}

///|
fn strongest_algorithm(items : Array[Metadata]) -> Algorithm? {
  guard items.get(0) is Some(first) else { return None }
  let mut strongest = first.algorithm
  for item in items {
    if item.algorithm.strength() > strongest.strength() {
      strongest = item.algorithm
    }
  }
  Some(strongest)
}

///|
fn verify_strongest(
  data : BytesView,
  items : Array[Metadata],
  strongest : Algorithm,
) -> Verdict {
  // The expected digest depends on the algorithm, not the number of candidates.
  let expected = encoded_digest(data, strongest)
  for item in items {
    if item.algorithm.strength() == strongest.strength() &&
      expected == item.digest {
      return Match
    }
  }
  Mismatch
}
