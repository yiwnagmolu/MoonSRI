///|
fn usage() -> Unit {
  println("Usage: moonsri generate <file> [algorithms]")
  println("       moonsri check <file> <integrity-metadata>")
  println(
    "       moonsri manifest [--algorithm algorithms] [--root dir] [--from files.txt] [--] [file...]",
  )
  println(
    "       moonsri check-manifest [--json] [--root dir] [--] <manifest.json>",
  )
  println("       moonsri diff-manifest <before.json> <after.json>")
  println(
    "Algorithms: sha256, sha384, sha512 (comma-separated; default: sha384)",
  )
}

///|
fn is_command(arg : String) -> Bool {
  match arg {
    "generate" | "check" | "manifest" | "check-manifest" | "diff-manifest" =>
      true
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
fn run(args : Array[String]) -> Int32 {
  // The JS runner includes `node` in argv; the Wasm runner does not.
  let command_index = if args.length() > 1 && is_command(args[1]) {
    1
  } else if args.length() > 2 && is_command(args[2]) {
    2
  } else {
    usage()
    return 2
  }
  let command = args[command_index]
  let operands = args[command_index + 1:]
  match command {
    "manifest" => return generate_manifest(operands)
    "check-manifest" => return run_check_manifest(operands)
    "diff-manifest" => return run_diff_manifest(operands)
    _ => ()
  }
  if (command == "generate" && (operands.length() < 1 || operands.length() > 2)) ||
    (command == "check" && operands.length() != 2) {
    usage()
    return 2
  }
  let algorithms = if command == "generate" && operands.length() == 2 {
    guard parse_algorithms(operands[1]) is Some(selected) else { return 2 }
    selected
  } else {
    [@sri.Sha384]
  }
  let path = operands[0]
  let data = @fs.read_file_to_bytes(path) catch {
    _ => {
      println("Cannot read file: " + path)
      return 2
    }
  }
  if command == "generate" {
    println(generate_metadata(data[:], algorithms))
    return 0
  }
  match @sri.verify_bytes(data[:], operands[1]) {
    @sri.Match => {
      println("match")
      0
    }
    @sri.Mismatch => {
      println("mismatch")
      1
    }
    @sri.NoSupportedMetadata => {
      println("no supported SRI metadata")
      2
    }
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
  @sys.exit(code)
}

///|
fn main {
  finish(run(@env.args()))
}
