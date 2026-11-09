///|
fn generate_manifest(args : ArrayView[String]) -> Int32 {
  let mut first_file = 0
  let mut algorithm = @sri.Sha384
  if args.length() > 0 && args[0] == "--algorithm" {
    if args.length() < 2 {
      usage()
      return 2
    }
    match parse_algorithm(args[1]) {
      Some(selected) => algorithm = selected
      None => {
        eprintln("Unknown algorithm: " + args[1])
        return 2
      }
    }
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
    manifest[path] = Json::string(@sri.generate(data[:], algorithm))
  }
  println(Json::object(manifest).stringify(indent=2))
  0
}

///|
fn valid_manifest_path(path : String) -> Bool {
  !path.is_empty() && !path.contains_char('\u{0000}')
}

///|
fn check_manifest(path : String) -> Int32 {
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
  for entry in assets {
    let (asset, integrity) = entry
    let quoted_asset = Json::string(asset).stringify()
    let bytes = @fs.read_file_to_bytes(asset) catch {
      _ => {
        eprintln("Cannot read file: " + quoted_asset)
        status = 2
        continue
      }
    }
    match @sri.verify_bytes(bytes[:], integrity) {
      @sri.Match => println("match: " + quoted_asset)
      @sri.Mismatch => {
        println("mismatch: " + quoted_asset)
        if status == 0 {
          status = 1
        }
      }
      @sri.NoSupportedMetadata => {
        eprintln("no supported SRI metadata: " + quoted_asset)
        status = 2
      }
    }
  }
  status
}
