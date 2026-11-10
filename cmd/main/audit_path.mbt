///|
priv enum AuditPath {
  Local(String)
  Directory(String)
  SameDocument
  External
  Invalid
}

///|
fn audit_base_directory(page : String, base : String) -> String? {
  let directory = parent_directory(page)
  match resolve_audit_path(directory, base) {
    Local(path) => Some(parent_directory(path))
    Directory(path) => Some(path)
    SameDocument => Some(directory)
    External | Invalid => None
  }
}

///|
fn parent_directory(path : String) -> String {
  match path.rev_split_once("/") {
    Some((parent, _)) => parent.to_owned()
    None => ""
  }
}

///|
fn resolve_audit_path(directory : String, raw_url : String) -> AuditPath {
  let url = raw_url.trim(chars=" \t\n\r\u{000c}")
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
    let absolute_url = if url.has_prefix("//") {
      "https:" + url.to_owned()
    } else {
      url.to_owned()
    }
    return if rest.is_empty() ||
      rest.has_prefix("/") ||
      rest.has_prefix("?") ||
      rest.has_prefix("#") ||
      !is_valid_http_url(absolute_url[:]) {
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
  if path.is_empty() {
    return SameDocument
  }
  if path == "/" {
    return Directory("")
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
  // A final slash names a directory. An empty segment elsewhere is ambiguous.
  let segments_path = relative.strip_suffix("/").unwrap_or(relative)
  let mut ends_in_file = false
  for raw in segments_path.split("/") {
    guard decode_url_segment(raw) is Some(segment) else { return Invalid }
    ends_in_file = false
    match segment {
      "." => ()
      ".." => {
        guard segments.pop() is Some(_) else { return Invalid }
      }
      _ => {
        guard is_portable_file_segment(segment[:]) else { return Invalid }
        segments.push(segment)
        ends_in_file = true
      }
    }
  }
  if ends_in_file && !path.has_suffix("/") {
    Local(segments.join("/"))
  } else {
    Directory(segments.join("/"))
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
