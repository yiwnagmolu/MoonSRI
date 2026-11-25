///|
priv enum ExpectedFile {
  Starting
  Target
  Absent
}

///|
priv struct LiveFinding {
  path : String
  expected : String
  status : String
}

///|
priv struct LiveReport {
  checked : Int32
  code : Int32
  findings : Array[LiveFinding]
}

///|
fn LiveReport::status(self : LiveReport) -> String {
  match self.code {
    0 => "match"
    1 => "drift"
    _ => "error"
  }
}

///|
fn LiveReport::to_json(self : LiveReport) -> Json {
  Json::object({
    "status": Json::string(self.status()),
    "checked": Json::number(self.checked.to_double()),
    "findings": Json::array(
      self.findings.map(f => {
        Json::object({
          "path": Json::string(f.path),
          "expected": Json::string(f.expected),
          "status": Json::string(f.status),
        })
      }),
    ),
  })
}

///|
/// A missing entry is established by a successful parent listing. A failed
/// listing must not be accepted as proof that a retired page is gone.
priv struct LiveDirectory {
  root : String
  entries : Map[String, Set[String]]
}

///|
fn LiveDirectory::contains(self : LiveDirectory, path : String) -> Bool raise {
  let mut directory = self.root
  for part in path.split("/") {
    let names = match self.entries.get(directory) {
      Some(names) => names
      None => {
        let names : Set[String] = Set([])
        for entry in @fs.read_dir(directory) {
          names.add(entry)
        }
        self.entries[directory] = names
        names
      }
    }
    let component = part.to_owned()
    let child = directory + component
    // The host may resolve another spelling (e.g. on a case-insensitive volume).
    if !names.contains(component) && !@fs.path_exists(child) {
      return false
    }
    directory = child + "/"
  }
  true
}

///|
fn verify_live_release(
  live_root : String,
  start_root : String,
  target_root : String,
  start_pages : Set[String],
  pages : Array[@rollout.Page],
  accepted : Array[(String, String)],
) -> LiveReport {
  let files : Map[String, ExpectedFile] = Map([])
  for page in pages {
    files[page.path] = if start_pages.contains(page.path) {
      Starting
    } else {
      Absent
    }
    for path, _ in page.before {
      files[path] = Starting
    }
  }
  for step in accepted {
    let (kind, path) = step
    files[path] = if kind == "retire_page" { Absent } else { Target }
  }
  let paths = files.keys().to_array()
  paths.sort_by((a, b) => a.lexical_compare(b))
  let live : LiveDirectory = { root: live_root, entries: Map([]), }
  let findings = []
  let mut code = 0
  for path in paths {
    let expected = files[path]
    let status = try {
      let exists = live.contains(path)
      match expected {
        Absent => if exists { "unexpected" } else { "match" }
        _ if !exists => "missing"
        _ if !@fs.is_file(live_root + path) => "not_file"
        Starting | Target => {
          let root = if expected is Starting { start_root } else { target_root }
          if generate_file_metadata(live_root + path, [@sri.Sha384]) ==
            generate_file_metadata(root + path, [@sri.Sha384]) {
            "match"
          } else {
            "different"
          }
        }
      }
    } catch {
      _ => "read_error"
    }
    if status != "match" {
      let origin = match expected {
        Starting => "start"
        Target => "target"
        Absent => "absent"
      }
      findings.push({ path, expected: origin, status, })
      if status == "read_error" {
        code = 2
      } else if code == 0 {
        code = 1
      }
    }
  }
  { checked: paths.length(), code, findings, }
}
