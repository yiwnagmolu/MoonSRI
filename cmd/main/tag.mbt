///|
fn run_tag(args : ArrayView[String]) -> Int32 {
  let kind = args.get(0)
  // A preload link reserves one operand for the fetch destination that
  // browsers attach to the request.
  let destination : String? = match kind {
    Some("preload") =>
      if args.length() == 4 || args.length() == 5 {
        guard parse_preload_destination(args[3]) is Some(value) else {
          return 2
        }
        Some(value)
      } else {
        usage()
        return 2
      }
    Some("script") | Some("stylesheet") | Some("modulepreload") =>
      if args.length() == 3 || args.length() == 4 {
        None
      } else {
        usage()
        return 2
      }
    _ => {
      eprintln("Expected a script, stylesheet, preload or modulepreload tag")
      return 2
    }
  }
  let kind = kind.unwrap()
  guard is_resource_url(args[2]) else {
    eprintln(
      "Expected a relative or HTTP(S) resource URL: " +
      Json::string(args[2]).stringify(),
    )
    return 2
  }
  let algorithms = if (kind == "preload" && args.length() == 5) ||
    (kind != "preload" && args.length() == 4) {
    guard parse_algorithms(args[args.length() - 1]) is Some(selected) else {
      return 2
    }
    selected
  } else {
    [@sri.Sha384]
  }
  let path = args[1]
  let metadata = generate_file_metadata(path, algorithms) catch {
    _ => {
      eprintln("Cannot read file: " + Json::string(path).stringify())
      return 2
    }
  }
  let escaped_url = escape_html_attribute(args[2])
  let attributes = "\" integrity=\"" + metadata + "\" crossorigin=\"anonymous\""
  match kind {
    "script" =>
      println("<script src=\"" + escaped_url + attributes + "></script>")
    "stylesheet" =>
      println(
        "<link rel=\"stylesheet\" href=\"" + escaped_url + attributes + ">",
      )
    "modulepreload" =>
      println(
        "<link rel=\"modulepreload\" href=\"" + escaped_url + attributes + ">",
      )
    _ => {
      let as_attribute = match destination {
        Some(value) => " as=\"" + value + "\""
        None => ""
      }
      println(
        "<link rel=\"preload\" href=\"" +
        escaped_url +
        "\"" +
        as_attribute +
        " integrity=\"" +
        metadata +
        "\" crossorigin=\"anonymous\">",
      )
    }
  }
  0
}

///|
fn parse_preload_destination(value : String) -> String? {
  let destinations = [
    "audio", "document", "embed", "fetch", "font", "image", "object", "script", "style",
    "track", "video", "worker",
  ]
  for name in destinations {
    if value.equal_ignore_ascii_case(name) {
      return Some(name)
    }
  }
  eprintln("Unknown preload destination: " + Json::string(value).stringify())
  None
}

///|
fn is_resource_url(url : String) -> Bool {
  if url.is_empty() || url.has_prefix("//") {
    return false
  }
  for char in url {
    // Browsers discard some control characters during URL parsing.
    if char <= ' ' || char == '\u{007f}' || char == '\\' {
      return false
    }
  }
  let normalized = url.to_lower()
  let authority = match normalized.strip_prefix("https://") {
    Some(rest) => Some(rest)
    None => normalized.strip_prefix("http://")
  }
  if authority is Some(rest) {
    return !rest.is_empty() &&
      !rest.has_prefix("/") &&
      !rest.has_prefix("?") &&
      !rest.has_prefix("#") &&
      is_valid_http_url(url[:])
  }
  // A colon before the first path delimiter can introduce a URL scheme.
  for char in url {
    if char == ':' {
      return false
    }
    if char == '/' || char == '?' || char == '#' {
      break
    }
  }
  true
}

///|
fn escape_html_attribute(input : String) -> String {
  let output = StringBuilder()
  for char in input {
    match char {
      '&' => output.write_string("&amp;")
      '"' => output.write_string("&quot;")
      '<' => output.write_string("&lt;")
      '>' => output.write_string("&gt;")
      _ => output.write_char(char)
    }
  }
  output.to_string()
}
