///|
fn generate_manifest(args : ArrayView[String]) -> Int32 {
  let mut first_file = 0
  let mut algorithms = None
  let mut root = None
  let mut list_path = None
  while first_file < args.length() {
    match args[first_file] {
      "--algorithm" if algorithms is None && first_file + 1 < args.length() => {
        guard parse_algorithms(args[first_file + 1]) is Some(selected) else {
          return 2
        }
        algorithms = Some(selected)
      }
      "--root" if root is None && first_file + 1 < args.length() => {
        guard parse_root(args[first_file + 1]) is Some(dir) else { return 2 }
        root = Some(dir)
      }
      "--from" if list_path is None && first_file + 1 < args.length() =>
        list_path = Some(args[first_file + 1])
      "--algorithm" | "--root" | "--from" => {
        usage()
        return 2
      }
      _ => break
    }
    first_file += 2
  }
  if first_file < args.length() && args[first_file] == "--" {
    first_file += 1
  }
  let paths = []
  if list_path is Some(path) {
    guard read_utf8_file(path, "asset list") is Some(source) else { return 2 }
    for line in source.split("\n") {
      let path = line.strip_suffix("\r").unwrap_or(line)
      if !path.is_empty() {
        paths.push(path.to_owned())
      }
    }
  }
  for path in args[first_file:] {
    paths.push(path)
  }
  if paths.is_empty() {
    eprintln("Manifest generation requires at least one asset path")
    usage()
    return 2
  }
  let algorithms = algorithms.unwrap_or([@sri.Sha384])
  let manifest : Map[String, String] = Map([])
  for path in paths {
    let quoted_path = Json::string(path).stringify()
    if !@manifest.is_asset_path(path) {
      eprintln("Invalid asset path: " + quoted_path)
      return 2
    }
    if manifest.contains(path) {
      eprintln("Duplicate asset path: " + quoted_path)
      return 2
    }
    guard resolve_asset(root, path) is Some(file) else { return 2 }
    let data = @fs.read_file_to_bytes(file) catch {
      _ => {
        eprintln("Cannot read file: " + quoted_path)
        return 2
      }
    }
    manifest[path] = generate_metadata(data[:], algorithms)
  }
  let output = @manifest.encode(manifest) catch {
    error => {
      eprintln(error.message())
      return 2
    }
  }
  println(output)
  0
}

///|
fn run_check_manifest(args : ArrayView[String]) -> Int32 {
  let mut json_output = false
  let mut root = None
  let mut minimum = None
  let mut index = 0
  while index < args.length() {
    match args[index] {
      "--json" if !json_output => {
        json_output = true
        index += 1
      }
      "--root" if root is None && index + 1 < args.length() => {
        guard parse_root(args[index + 1]) is Some(dir) else { return 2 }
        root = Some(dir)
        index += 2
      }
      "--min-algorithm" if minimum is None && index + 1 < args.length() => {
        guard parse_minimum(args[index + 1]) is Some(algorithm) else {
          return 2
        }
        minimum = Some(algorithm)
        index += 2
      }
      "--json" | "--root" | "--min-algorithm" => {
        usage()
        return 2
      }
      _ => break
    }
  }
  if index < args.length() && args[index] == "--" {
    index += 1
  }
  if args.length() != index + 1 {
    usage()
    return 2
  }
  check_manifest(args[index], json_output, root, minimum)
}

///|
fn parse_root(dir : String) -> String? {
  if !@manifest.is_asset_path(dir) {
    eprintln("Invalid asset root: " + Json::string(dir).stringify())
    return None
  }
  Some(dir)
}

///|
fn resolve_asset(root : String?, path : String) -> String? {
  guard root is Some(dir) else { return Some(path) }
  let valid = !path.contains_char('\\') &&
    !path.contains_char(':') &&
    path
    .split("/")
    .all(part => {
      !part.is_empty() && !part.has_suffix(".") && !part.has_suffix(" ")
    })
  if !valid {
    eprintln(
      "Expected a portable relative asset path: " +
      Json::string(path).stringify(),
    )
    return None
  }
  Some(dir + "/" + path)
}

///|
fn check_manifest(
  path : String,
  json_output : Bool,
  root : String?,
  minimum : @sri.Algorithm?,
) -> Int32 {
  guard read_manifest(path) is Some(assets) else { return 2 }
  let files : Array[(String, String, String)] = []
  for asset, integrity in assets {
    guard resolve_asset(root, asset) is Some(file) else { return 2 }
    files.push((asset, file, integrity))
  }
  let mut status = 0
  let report : Map[String, Json] = Map([])
  for entry in files {
    let (asset, file, integrity) = entry
    let (code, result, message) = check_manifest_asset(file, integrity, minimum)
    if code > status {
      status = code
    }
    if json_output {
      report[asset] = Json::string(result)
    } else {
      let line = message + ": " + Json::string(asset).stringify()
      if code == 2 {
        eprintln(line)
      } else {
        println(line)
      }
    }
  }
  if json_output {
    println(Json::object(report).stringify(indent=2))
  }
  status
}

///|
fn read_utf8_file(path : String, description : String) -> String? {
  let quoted_path = Json::string(path).stringify()
  let data = @fs.read_file_to_bytes(path) catch {
    _ => {
      eprintln("Cannot read " + description + ": " + quoted_path)
      return None
    }
  }
  let source = @utf8.decode(data[:], ignore_bom=true) catch {
    _ => {
      eprintln("Expected UTF-8 " + description + ": " + quoted_path)
      return None
    }
  }
  Some(source)
}

///|
fn read_manifest(path : String) -> Map[String, String]? {
  guard read_utf8_file(path, "manifest") is Some(source) else { return None }
  let assets = @manifest.parse(source) catch {
    error => {
      eprintln(error.message())
      return None
    }
  }
  Some(assets)
}

///|
fn run_diff_manifest(args : ArrayView[String]) -> Int32 {
  guard args.length() == 2 else {
    usage()
    return 2
  }
  guard read_manifest(args[0]) is Some(before) else { return 2 }
  guard read_manifest(args[1]) is Some(after) else { return 2 }
  let changes = @manifest.diff(before, after)
  for change in changes {
    match change {
      @manifest.Added(path, value) =>
        println(
          "added: " +
          Json::string(path).stringify() +
          " " +
          Json::string(value).stringify(),
        )
      @manifest.Removed(path, value) =>
        println(
          "removed: " +
          Json::string(path).stringify() +
          " " +
          Json::string(value).stringify(),
        )
      @manifest.Changed(path, old, current) =>
        println(
          "changed: " +
          Json::string(path).stringify() +
          " " +
          Json::string(old).stringify() +
          " -> " +
          Json::string(current).stringify(),
        )
    }
  }
  if changes.is_empty() {
    0
  } else {
    1
  }
}

///|
fn check_manifest_asset(
  asset : String,
  integrity : String,
  minimum : @sri.Algorithm?,
) -> (Int32, String, String) {
  let bytes = @fs.read_file_to_bytes(asset) catch {
    _ => return (2, "read_error", "Cannot read file")
  }
  check_metadata(bytes[:], integrity, minimum)
}
