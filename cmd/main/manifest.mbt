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
    let data = @fs.read_file_to_bytes(path) catch {
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
  guard read_manifest(path) is Some(assets) else { return 2 }
  let mut status = 0
  let report : Map[String, Json] = Map([])
  for asset, integrity in assets {
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
