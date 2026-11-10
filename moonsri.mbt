///|
/// SRI 1.0 algorithms supported by this library.
#derive(Eq, Hash)
pub(all) enum Algorithm {
  Sha256
  Sha384
  Sha512
}

///|
pub extend Algorithm with Eq::{equal, not_equal}

///|
pub extend Algorithm with Hash::{hash, hash_combine}

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
  let digest = match algorithm {
    Sha256 => @crypto.sha256(data)
    Sha384 => @crypto.sha384(data)
    Sha512 => @crypto.sha512(data)
  }
  let digest = Bytes::from_array(digest[:])
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
fn parse_token(token : StringView) -> Metadata? {
  // SRI reads the expression before '?' and the digest in its second field.
  let expression = match token.split_once("?") {
    Some((expression, _)) => expression
    None => token
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
  let mut start = 0
  let mut offset = 0
  for ch in input {
    let end = offset
    offset += ch.utf16_len()
    if is_metadata_space(ch) {
      if start < end &&
        parse_token(input.exact_view(start~, end~)) is Some(item) {
        result.push(item)
      }
      start = offset
    }
  }
  if start < offset && parse_token(input.exact_view(start~)) is Some(item) {
    result.push(item)
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
/// Normalize the effective digest set to its strongest recognized algorithm.
/// Digest case is preserved; duplicate digests are removed and the rest sorted.
pub fn canonical_metadata(input : String) -> String? {
  let items = parse_metadata(input)
  if items.length() == 1 {
    let item = items[0]
    return Some(item.algorithm.label() + "-" + item.digest)
  }
  guard strongest_algorithm(items) is Some(strongest) else { return None }
  let digests : Set[String] = Set([])
  for item in items {
    if item.algorithm == strongest {
      digests.add(item.digest)
    }
  }
  let sorted = digests.iter().to_array()
  sorted.sort_by((left, right) => left.lexical_compare(right))
  let prefix = strongest.label() + "-"
  Some(sorted.map(digest => prefix + digest).join(" "))
}

///|
/// Verify with a minimum algorithm strength. Err contains the strongest
/// advertised algorithm when it falls below the minimum.
pub fn verify_bytes_at_least(
  data : BytesView,
  input : String,
  minimum : Algorithm,
) -> Result[Verdict, Algorithm] {
  verify_using(input, Some(minimum), (items, algorithm) => {
    verify_strongest(data, items, algorithm)
  })
}

///|
/// Verify against a token computed for the selected algorithm and resource,
/// such as the output of `generate`. The provider runs only when hashing is
/// required, so callers can reuse a digest across different declarations.
pub fn verify_with_token(
  input : String,
  token_for : (Algorithm) -> String raise?,
  minimum~ : Algorithm? = None,
) -> Result[Verdict, Algorithm] raise? {
  verify_using(input, minimum, (items, algorithm) => {
    let token = token_for(algorithm)
    guard token.strip_prefix(algorithm.label() + "-") is Some(digest) else {
      return Mismatch
    }
    verify_digest(items, algorithm, digest)
  })
}

///|
fn verify_using(
  input : String,
  minimum : Algorithm?,
  verify : (Array[Metadata], Algorithm) -> Verdict raise?,
) -> Result[Verdict, Algorithm] raise? {
  let items = parse_metadata(input)
  guard strongest_algorithm(items) is Some(strongest) else {
    return Ok(NoSupportedMetadata)
  }
  if minimum is Some(minimum) && strongest.strength() < minimum.strength() {
    return Err(strongest)
  }
  Ok(verify(items, strongest))
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
  verify_digest(items, strongest, expected[:])
}

///|
fn verify_digest(
  items : Array[Metadata],
  strongest : Algorithm,
  expected : StringView,
) -> Verdict {
  for item in items {
    if item.algorithm == strongest && expected == item.digest[:] {
      return Match
    }
  }
  Mismatch
}
