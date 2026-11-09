///|
fn generate_manifest(args : ArrayView[String]) -> Int32 {
  let mut first_file = 0
  let mut algorithms = None
  let mut root = None
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
      "--algorithm" | "--root" => {
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
  if first_file == args.length() {
    usage()
    return 2
  }
  let algorithms = algorithms.unwrap_or([@sri.Sha384])
  let manifest : Map[String, String] = Map([])
  for path in args[first_file:] {
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
      "--json" | "--root" => {
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
  check_manifest(args[index], json_output, root)
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
fn check_manifest(path : String, json_output : Bool, root : String?) -> Int32 {
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
    let (code, result, message) = check_manifest_asset(file, integrity)
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
fn read_manifest(path : String) -> Map[String, String]? {
  let data = @fs.read_file_to_bytes(path) catch {
    _ => {
      eprintln("Cannot read manifest: " + path)
      return None
    }
  }
  let source = @utf8.decode(data[:], ignore_bom=true) catch {
    _ => {
      eprintln("Manifest must be UTF-8")
      return None
    }
  }
  let assets = @manifest.parse(source) catch {
    error => {
      eprintln(error.message())
      return None
    }
  }
  Some(assets)
}

///|
fn check_manifest_asset(
  asset : String,
  integrity : String,
) -> (Int32, String, String) {
  let bytes = @fs.read_file_to_bytes(asset) catch {
    _ => return (2, "read_error", "Cannot read file")
  }
  match @sri.verify_bytes(bytes[:], integrity) {
    @sri.Match => (0, "match", "match")
    @sri.Mismatch => (1, "mismatch", "mismatch")
    @sri.NoSupportedMetadata =>
      (2, "no_supported_metadata", "no supported SRI metadata")
  }
}
