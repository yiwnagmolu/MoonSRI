///|
fn run_audit_html(args : ArrayView[String]) -> Int32 {
  let mut root = None
  let mut json_output = false
  let mut minimum = None
  let mut index = 0
  while index < args.length() {
    match args[index] {
      "--root" if root is None && index + 1 < args.length() => {
        guard parse_root_prefix(args[index + 1]) is Some(prefix) else {
          return 2
        }
        root = Some(prefix)
        index += 2
      }
      "--json" if !json_output => {
        json_output = true
        index += 1
      }
      "--min-algorithm" if minimum is None && index + 1 < args.length() => {
        guard parse_minimum(args[index + 1]) is Some(algorithm) else {
          return 2
        }
        minimum = Some(algorithm)
        index += 2
      }
      "--" => {
        index += 1
        break
      }
      option if option.has_prefix("--") => {
        usage()
        return 2
      }
      _ => break
    }
  }
  guard root is Some(prefix) && index < args.length() else {
    usage()
    return 2
  }
  let reports : Array[Json] = []
  let mut code = 0
  for page in args[index:] {
    let (page_code, report) = audit_page(prefix, page, minimum, json_output)
    if page_code > code {
      code = page_code
    }
    if report is Some(report) {
      reports.push(report)
    }
  }
  if json_output {
    println(Json::array(reports).stringify(indent=2))
  }
  code
}

///|
fn audit_page(
  prefix : String,
  page : String,
  minimum : @sri.Algorithm?,
  json_output : Bool,
) -> (Int32, Json?) {
  let quoted = Json::string(page).stringify()
  guard page.split("/").all(part => is_audit_file_segment(part.to_owned())) else {
    eprintln("Expected a relative HTML page path: " + quoted)
    return (2, audit_report(page, "invalid_page_path", [], json_output))
  }
  guard read_utf8_file(prefix + page, "HTML page") is Some(source) else {
    return (2, audit_report(page, "read_error", [], json_output))
  }
  let doc = @audit.scan(source)
  let directory = match doc.base_href {
    None | Some("") =>
      match page.rev_split_once("/") {
        Some((parent, _)) => parent.to_owned()
        None => ""
      }
    Some("/") => ""
    Some(base) => {
      eprintln(
        "Unsupported base href in " +
        quoted +
        ": " +
        Json::string(base).stringify(),
      )
      return (2, audit_report(page, "unsupported_base", [], json_output))
    }
  }
  let resources : Array[Json] = []
  let mut code = 0
  for reference in doc.references {
    let (resource_code, status, path) = audit_reference(
      prefix, directory, reference, minimum,
    )
    if resource_code > code {
      code = resource_code
    }
    let kind = match reference.kind {
      @audit.Script => "script"
      @audit.Stylesheet => "stylesheet"
    }
    if json_output {
      let entry = Map([
        ("kind", Json::string(kind)),
        ("url", Json::string(reference.url)),
        ("status", Json::string(status)),
      ])
      if path is Some(path) {
        entry["path"] = Json::string(path)
      }
      resources.push(Json::object(entry))
    } else {
      println(
        status +
        ": " +
        quoted +
        " " +
        kind +
        " " +
        Json::string(reference.url).stringify(),
      )
    }
  }
  if !json_output && doc.references.is_empty() {
    println("no static resources: " + quoted)
  }
  (
    code,
    audit_report(
      page,
      if code == 0 {
        "ok"
      } else {
        "failed"
      },
      resources,
      json_output,
    ),
  )
}

///|
fn audit_report(
  page : String,
  status : String,
  resources : Array[Json],
  json_output : Bool,
) -> Json? {
  if json_output {
    Some(
      Json::object(
        Map([
          ("page", Json::string(page)),
          ("status", Json::string(status)),
          ("resources", Json::array(resources)),
        ]),
      ),
    )
  } else {
    None
  }
}

///|
fn audit_reference(
  prefix : String,
  directory : String,
  reference : @audit.Reference,
  minimum : @sri.Algorithm?,
) -> (Int32, String, String?) {
  match resolve_audit_path(directory, reference.url) {
    External => (0, "external", None)
    Invalid => (2, "invalid_url", None)
    Local(path) => {
      let integrity = reference.integrity.unwrap_or("")
      if integrity.trim(chars=" \t\n\r\u{000c}").is_empty() {
        return (1, "missing_integrity", Some(path))
      }
      let (code, status, _) = check_file_metadata(
        prefix + path,
        integrity,
        minimum,
      )
      (code, status, Some(path))
    }
  }
}
