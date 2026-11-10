///|
fn usage() -> Unit {
  eprintln("Usage: moonsri generate <file> [algorithms]")
  eprintln("       moonsri tag <script|stylesheet> <file> <url> [algorithms]")
  eprintln(
    "       moonsri check <file> <integrity-metadata> [--min-algorithm algorithm]",
  )
  eprintln(
    "       moonsri manifest [--algorithm algorithms] [--root dir] [--from files.txt] [--] [file...]",
  )
  eprintln(
    "       moonsri check-manifest [--json] [--root dir] [--min-algorithm algorithm] [--] <manifest.json>",
  )
  eprintln("       moonsri diff-manifest <before.json> <after.json>")
  eprintln(
    "Algorithms: sha256, sha384, sha512 (comma-separated; default: sha384)",
  )
}

///|
fn is_command(arg : String) -> Bool {
  match arg {
    "generate"
    | "tag"
    | "check"
    | "manifest"
    | "check-manifest"
    | "diff-manifest" => true
    _ => false
  }
}

///|
fn parse_algorithm(name : String) -> @sri.Algorithm? {
  match name {
    "sha256" => Some(@sri.Sha256)
    "sha384" => Some(@sri.Sha384)
    "sha512" => Some(@sri.Sha512)
    _ => None
  }
}

///|
fn parse_algorithms(input : String) -> Array[@sri.Algorithm]? {
  let algorithms = []
  let names : Set[String] = Set([])
  for part in input.split(",") {
    let name = part.to_owned()
    guard parse_algorithm(name) is Some(algorithm) else {
      eprintln("Unknown algorithm: " + Json::string(name).stringify())
      return None
    }
    if names.contains(name) {
      eprintln("Duplicate algorithm: " + name)
      return None
    }
    names.add(name)
    algorithms.push(algorithm)
  }
  Some(algorithms)
}

///|
fn generate_metadata(
  data : BytesView,
  algorithms : Array[@sri.Algorithm],
) -> String {
  algorithms.map(algorithm => @sri.generate(data, algorithm)).join(" ")
}

///|
// Node includes the executable and script path. Moon's other hosts pass one
// executable prefix.
#cfg(target="js")
let command_index : Int32 = 2

///|
#cfg(not(target="js"))
let command_index : Int32 = 1

///|
fn run(args : Array[String]) -> Int32 {
  guard args.get(command_index) is Some(command) && is_command(command) else {
    usage()
    return 2
  }
  let operands = args[command_index + 1:]
  match command {
    "tag" => return run_tag(operands)
    "manifest" => return generate_manifest(operands)
    "check-manifest" => return run_check_manifest(operands)
    "diff-manifest" => return run_diff_manifest(operands)
    _ => ()
  }
  if (command == "generate" && (operands.length() < 1 || operands.length() > 2)) ||
    (
      command == "check" &&
      operands.length() != 2 &&
      (operands.length() != 4 || operands[2] != "--min-algorithm")
    ) {
    usage()
    return 2
  }
  let algorithms = if command == "generate" && operands.length() == 2 {
    guard parse_algorithms(operands[1]) is Some(selected) else { return 2 }
    selected
  } else {
    [@sri.Sha384]
  }
  let minimum = if command == "check" && operands.length() == 4 {
    guard parse_minimum(operands[3]) is Some(selected) else { return 2 }
    Some(selected)
  } else {
    None
  }
  let path = operands[0]
  let data = @fs.read_file_to_bytes(path) catch {
    _ => {
      eprintln("Cannot read file: " + Json::string(path).stringify())
      return 2
    }
  }
  if command == "generate" {
    println(generate_metadata(data[:], algorithms))
    return 0
  }
  let (code, _, message) = check_metadata(data[:], operands[1], minimum)
  println(message)
  code
}

///|
fn parse_minimum(name : String) -> @sri.Algorithm? {
  guard parse_algorithm(name) is Some(algorithm) else {
    eprintln("Unknown minimum algorithm: " + Json::string(name).stringify())
    return None
  }
  Some(algorithm)
}

///|
fn check_metadata(
  bytes : BytesView,
  integrity : String,
  minimum : @sri.Algorithm?,
) -> (Int32, String, String) {
  let verdict = match minimum {
    Some(algorithm) =>
      match @sri.verify_bytes_at_least(bytes, integrity, algorithm) {
        Ok(verdict) => verdict
        Err(_) => return (1, "below_minimum", "below minimum algorithm")
      }
    None => @sri.verify_bytes(bytes, integrity)
  }
  match verdict {
    @sri.Match => (0, "match", "match")
    @sri.Mismatch => (1, "mismatch", "mismatch")
    @sri.NoSupportedMetadata =>
      (2, "no_supported_metadata", "no supported SRI metadata")
  }
}

///|
/// Let Node finish writing piped reports before exiting.
#cfg(target="js")
extern "js" fn finish(code : Int32) -> Unit =
  #| (code) => { process.exitCode = code; }

///|
#cfg(not(target="js"))
fn finish(code : Int32) -> Unit {
  @env.exit(code)
}

///|
fn main {
  finish(run(@env.args()))
}
