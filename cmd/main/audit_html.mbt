///|
priv struct AuditRun {
  prefix : String
  minimum : @sri.Algorithm?
  baseline : Map[String, String]?
  verdicts : Map[(String, String), (Int32, String)]
}

///|
priv struct AuditFinding {
  code : Int32
  status : String
  path : String?
  baseline : BaselineCheck?
}

///|
fn run_audit_html(args : ArrayView[String]) -> Int32 {
  let mut root = None
  let mut json_output = false
  let mut minimum = None
  let mut baseline_path = None
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
      "--baseline" if baseline_path is None && index + 1 < args.length() => {
        baseline_path = Some(args[index + 1])
        index += 2
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
  let baseline = match baseline_path {
    Some(path) => {
      guard read_audit_baseline(path) is Some(entries) else { return 2 }
      Some(entries)
    }
    None => None
  }
  let run : AuditRun = { prefix, minimum, baseline, verdicts: Map([]), }
  let mut code = 0
  for page in args[index:] {
    let (page_code, report) = audit_page(run, page, json_output)
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
  run : AuditRun,
  page : String,
  json_output : Bool,
) -> (Int32, Json?) {
  let quoted = Json::string(page).stringify()
  guard is_portable_relative_path(page) else {
    eprintln("Expected a relative HTML page path: " + quoted)
    return (2, audit_report(page, "invalid_page_path", [], json_output))
  }
  guard read_utf8_file(run.prefix + page, "HTML page") is Some(source) else {
    return (2, audit_report(page, "read_error", [], json_output))
  }
  let doc = @audit.scan(source)
  let base = doc.base_href.unwrap_or("")
  guard audit_base_directory(page, base) is Some(directory) else {
    eprintln(
      "Unsupported base href in " +
      quoted +
      ": " +
      Json::string(base).stringify(),
    )
    return (2, audit_report(page, "unsupported_base", [], json_output))
  }
  let resources : Array[Json] = []
  let mut code = 0
  for reference in doc.references {
    let finding = audit_reference(run, directory, reference)
    if finding.code > code {
      code = finding.code
    }
    let kind = match reference.kind {
      @audit.Script => "script"
      @audit.Stylesheet => "stylesheet"
    }
    if json_output {
      let entry = Map([
        ("kind", Json::string(kind)),
        ("url", Json::string(reference.url)),
        ("status", Json::string(finding.status)),
      ])
      if finding.path is Some(path) {
        entry["path"] = Json::string(path)
      }
      if finding.baseline is Some(baseline) {
        entry["baseline"] = Json::object(
          Map([
            ("declaration", Json::string(baseline.declaration)),
            ("content", Json::string(baseline.content)),
          ]),
        )
      }
      resources.push(Json::object(entry))
    } else {
      let baseline = match finding.baseline {
        None => ""
        Some(check) =>
          " [baseline declaration=" +
          check.declaration +
          " content=" +
          check.content +
          "]"
      }
      println(
        finding.status +
        ": " +
        quoted +
        " " +
        kind +
        " " +
        Json::string(reference.url).stringify() +
        baseline,
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
  run : AuditRun,
  directory : String,
  reference : @audit.Reference,
) -> AuditFinding {
  match resolve_audit_path(directory, reference.url) {
    External => { code: 0, status: "external", path: None, baseline: None, }
    Directory(_) | SameDocument | Invalid =>
      { code: 2, status: "invalid_url", path: None, baseline: None, }
    Local(path) => {
      let integrity = reference.integrity.unwrap_or("")
      let declared = if run.baseline is Some(_) {
        @sri.canonical_metadata(integrity)
      } else {
        None
      }
      let (code, status) = if integrity.trim(chars=" \t\n\r\u{000c}").is_empty() {
        (1, "missing_integrity")
      } else {
        run.verify_file(path, declared.unwrap_or(integrity))
      }
      let (baseline_code, baseline) = run.check_baseline(path, declared)
      let code = if baseline_code > code { baseline_code } else { code }
      { code, status, path: Some(path), baseline, }
    }
  }
}

///|
fn AuditRun::verify_file(
  self : AuditRun,
  path : String,
  integrity : String,
) -> (Int32, String) {
  let key = (path, integrity)
  if self.verdicts.get(key) is Some(verdict) {
    return verdict
  }
  let (code, status, _) = check_file_metadata(
    self.prefix + path,
    integrity,
    self.minimum,
  )
  let verdict = (code, status)
  self.verdicts[key] = verdict
  verdict
}
