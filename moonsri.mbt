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
  let kind = match algorithm {
    Sha256 => @sha2.Sha256
    Sha384 => @sha2.Sha384
    Sha512 => @sha2.Sha512
  }
  let digest = @sha2.hash(data, kind~)
  algorithm.label() + "-" + @base64.encode(digest[:])
}

///|
fn is_metadata_space(ch : Char) -> Bool {
  ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' || ch == '\u{000c}'
}

///|
fn parse_token(token : String) -> Metadata? {
  // SRI 1.0 defines no options. Preserve the hash expression before '?'.
  let expression = token.split("?").to_array()[0]
  let parts = expression.split("-").to_array()
  let algorithm = match parts[0].to_lower() {
    "sha256" => Sha256
    "sha384" => Sha384
    "sha512" => Sha512
    _ => return None
  }
  let digest = if parts.length() > 1 { parts[1].to_owned() } else { "" }
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
  if items.is_empty() {
    return NoSupportedMetadata
  }
  let mut strongest = 0
  for item in items {
    if item.algorithm.strength() > strongest {
      strongest = item.algorithm.strength()
    }
  }
  for item in items {
    if item.algorithm.strength() == strongest {
      let expected = generate(data, item.algorithm)
      if expected == item.algorithm.label() + "-" + item.digest {
        return Match
      }
    }
  }
  Mismatch
}
