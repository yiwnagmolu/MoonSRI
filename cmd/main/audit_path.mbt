///|
priv enum AuditPath {
  Local(String)
  External
  Invalid
}

///|
fn resolve_audit_path(directory : String, raw_url : String) -> AuditPath {
  let url = raw_url.trim(chars=" \t\n\r\u{000c}")
  if url.is_empty() {
    return Invalid
  }
  for ch in url {
    if ch < ' ' || ch == '\u{007f}' || ch == '\\' {
      return Invalid
    }
  }
  let authority = if url.strip_prefix("//") is Some(rest) {
    Some(rest)
  } else if url.split_once("://") is Some((scheme, rest)) &&
    (
      scheme.equal_ignore_ascii_case("https") ||
      scheme.equal_ignore_ascii_case("http")
    ) {
    Some(rest)
  } else {
    None
  }
  if authority is Some(rest) {
    return if rest.is_empty() ||
      rest.has_prefix("/") ||
      rest.has_prefix("?") ||
      rest.has_prefix("#") {
      Invalid
    } else {
      External
    }
  }
  let path = match url.split_once("#") {
    Some((path, _)) => path
    None => url
  }
  let path = match path.split_once("?") {
    Some((path, _)) => path
    None => path
  }
  let segments : Array[String] = []
  let relative = match path.strip_prefix("/") {
    Some(relative) => relative
    None => {
      if !directory.is_empty() {
        for segment in directory.split("/") {
          segments.push(segment.to_owned())
        }
      }
      path
    }
  }
  let mut ends_in_file = false
  for raw in relative.split("/") {
    guard decode_url_segment(raw) is Some(segment) else { return Invalid }
    ends_in_file = false
    match segment {
      "." => ()
      ".." => {
        guard segments.pop() is Some(_) else { return Invalid }
      }
      _ => {
        guard is_audit_file_segment(segment) else { return Invalid }
        segments.push(segment)
        ends_in_file = true
      }
    }
  }
  if ends_in_file {
    Local(segments.join("/"))
  } else {
    Invalid
  }
}

///|
fn is_audit_file_segment(segment : String) -> Bool {
  if segment.is_empty() || segment.has_suffix(".") || segment.has_suffix(" ") {
    return false
  }
  for ch in segment {
    if ch < ' ' || ch == '\u{007f}' || "/\\:<>\"|?*".contains_char(ch) {
      return false
    }
  }
  // Windows treats these basenames as devices even with a file extension.
  let name = match segment.split_once(".") {
    Some((stem, _)) => stem.trim_end(chars=" ").to_lower().to_owned()
    None => segment.to_lower()
  }
  match name {
    "con" | "prn" | "aux" | "nul" | "conin$" | "conout$" => false
    _ => {
      if name.has_prefix("com") || name.has_prefix("lpt") {
        let suffix = name.exact_view(start=3)
        return !("123456789¹²³".contains(suffix) && suffix.char_length() == 1)
      }
      true
    }
  }
}

///|
fn decode_url_segment(segment : StringView) -> String? {
  if !segment.contains_char('%') {
    return Some(segment.to_owned())
  }
  let input = @utf8.encode(segment)
  let output : Array[Byte] = []
  let mut index = 0
  while index < input.length() {
    if input[index] == b'%' {
      guard index + 2 < input.length() &&
        hex_digit(input[index + 1]) is Some(high) &&
        hex_digit(input[index + 2]) is Some(low) else {
        return None
      }
      output.push((high * 16 + low).to_byte())
      index += 3
    } else {
      output.push(input[index])
      index += 1
    }
  }
  let bytes = Bytes::from_array(output[:])
  Some(@utf8.decode(bytes[:], ignore_bom=false)) catch {
    _ => None
  }
}

///|
fn hex_digit(value : Byte) -> Int32? {
  if value >= b'0' && value <= b'9' {
    Some(value.to_int() - b'0'.to_int())
  } else if value >= b'a' && value <= b'f' {
    Some(value.to_int() - b'a'.to_int() + 10)
  } else if value >= b'A' && value <= b'F' {
    Some(value.to_int() - b'A'.to_int() + 10)
  } else {
    None
  }
}
