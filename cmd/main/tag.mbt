///|
fn run_tag(args : ArrayView[String]) -> Int32 {
  guard args.length() == 3 || args.length() == 4 else {
    usage()
    return 2
  }
  let kind = args[0]
  guard kind == "script" || kind == "stylesheet" else {
    eprintln("Expected a script or stylesheet tag")
    return 2
  }
  let url = args[2]
  guard is_resource_url(url) else {
    eprintln(
      "Expected a relative or HTTP(S) resource URL: " +
      Json::string(url).stringify(),
    )
    return 2
  }
  let algorithms = if args.length() == 4 {
    guard parse_algorithms(args[3]) is Some(selected) else { return 2 }
    selected
  } else {
    [@sri.Sha384]
  }
  let path = args[1]
  let bytes = @fs.read_file_to_bytes(path) catch {
    _ => {
      eprintln("Cannot read file: " + Json::string(path).stringify())
      return 2
    }
  }
  let escaped_url = escape_html_attribute(url)
  let metadata = generate_metadata(bytes[:], algorithms)
  let attributes = "\" integrity=\"" + metadata + "\" crossorigin=\"anonymous\""
  if kind == "script" {
    println("<script src=\"" + escaped_url + attributes + "></script>")
  } else {
    println("<link rel=\"stylesheet\" href=\"" + escaped_url + attributes + ">")
  }
  0
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
      !rest.has_prefix("#")
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
