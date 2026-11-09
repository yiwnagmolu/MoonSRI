///|
fn generate_manifest(args : ArrayView[String]) -> Int32 {
  let mut first_file = 0
  let mut algorithms = [@sri.Sha384]
  if args.length() > 0 && args[0] == "--algorithm" {
    if args.length() < 2 {
      usage()
      return 2
    }
    guard parse_algorithms(args[1]) is Some(selected) else { return 2 }
    algorithms = selected
    first_file = 2
  }
  if first_file < args.length() && args[first_file] == "--" {
    first_file += 1
  }
  if first_file == args.length() {
    usage()
    return 2
  }
  let manifest : Map[String, Json] = Map([])
  for path in args[first_file:] {
    let quoted_path = Json::string(path).stringify()
    if !valid_manifest_path(path) {
      eprintln("Invalid asset path: " + quoted_path)
      return 2
    }
    if manifest.contains(path) {
      eprintln("Duplicate asset path: " + quoted_path)
      return 2
    }
    let data = @fs.read_file_to_bytes(path) catch {
      _ => {
        eprintln("Cannot read file: " + quoted_path)
        return 2
      }
    }
    manifest[path] = Json::string(generate_metadata(data[:], algorithms))
  }
  println(Json::object(manifest).stringify(indent=2))
  0
}

///|
fn valid_manifest_path(path : String) -> Bool {
  !path.is_empty() && !path.contains_char('\u{0000}')
}

///|
fn run_check_manifest(args : ArrayView[String]) -> Int32 {
  let json_output = args.length() > 0 && args[0] == "--json"
  let mut index = if json_output { 1 } else { 0 }
  if index < args.length() && args[index] == "--" {
    index += 1
  }
  if args.length() != index + 1 {
    usage()
    return 2
  }
  check_manifest(args[index], json_output)
}

///|
fn check_manifest(path : String, json_output : Bool) -> Int32 {
  let data = @fs.read_file_to_bytes(path) catch {
    _ => {
      eprintln("Cannot read manifest: " + path)
      return 2
    }
  }
  let source = @utf8.decode(data[:], ignore_bom=true) catch {
    _ => {
      eprintln("Manifest must be UTF-8")
      return 2
    }
  }
  let parsed = @json.parse(source, reject_duplicate_keys=true) catch {
    error => {
      eprintln("Invalid manifest JSON: " + error.to_string())
      return 2
    }
  }
  let manifest = match parsed {
    Object(entries) if !entries.is_empty() => entries
    _ => {
      eprintln("Manifest must be a non-empty JSON object")
      return 2
    }
  }
  let assets : Array[(String, String)] = []
  for asset, value in manifest {
    let quoted_asset = Json::string(asset).stringify()
    guard valid_manifest_path(asset) else {
      eprintln("Invalid asset path: " + quoted_asset)
      return 2
    }
    guard value is String(integrity) else {
      eprintln("Expected a string for asset: " + quoted_asset)
      return 2
    }
    assets.push((asset, integrity))
  }
  let mut status = 0
  let report : Map[String, Json] = Map([])
  for entry in assets {
    let (asset, integrity) = entry
    let (code, result, message) = check_manifest_asset(asset, integrity)
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
