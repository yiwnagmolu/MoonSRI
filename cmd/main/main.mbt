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
    "       moonsri audit-html --root dir [--baseline manifest.json] [--json] [--min-algorithm algorithm] [--] <page>...",
  )
  eprintln(
    "       moonsri diff-html --before-root dir --after-root dir [--json] [--] <page>...",
  )
  eprintln(
    "       moonsri review-release --before-root dir --after-root dir [--json] [--] <page>...",
  )
  eprintln(
    "       moonsri review-release --before-root dir --after-root dir --before-pages old.txt --after-pages new.txt [--json]",
  )
  eprintln(
    "       review-release options: [--rollback] [--check-order steps.json [--require-complete] [--verify-live dir]]",
  )
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
    | "diff-manifest"
    | "audit-html"
    | "diff-html"
    | "review-release" => true
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
    "audit-html" => return run_audit_html(operands)
    "diff-html" => return run_diff_html(operands)
    "review-release" => return run_review_release(operands)
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
  if command == "generate" {
    let metadata = generate_file_metadata(path, algorithms) catch {
      _ => {
        eprintln("Cannot read file: " + Json::string(path).stringify())
        return 2
      }
    }
    println(metadata)
    return 0
  }
  let (code, status, message) = check_file_metadata(path, operands[1], minimum)
  if status == "read_error" {
    eprintln(message + ": " + Json::string(path).stringify())
  } else {
    println(message)
  }
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
  integrity : String,
  minimum : @sri.Algorithm?,
  generate : (Array[@sri.Algorithm]) -> String raise,
) -> (Int32, String, String) {
  try {
    let verdict = @sri.verify_with_token(
      integrity,
      algorithm => generate([algorithm]),
      minimum~,
    )
    // Check readability even when the declaration did not need a digest.
    if verdict is Err(_) || verdict is Ok(@sri.NoSupportedMetadata) {
      ignore(generate([]))
    }
    describe_verification(verdict)
  } catch {
    _ => (2, "read_error", "Cannot read file")
  }
}

///|
fn describe_verification(
  result : Result[@sri.Verdict, @sri.Algorithm],
) -> (Int32, String, String) {
  match result {
    Ok(@sri.Match) => (0, "match", "match")
    Ok(@sri.Mismatch) => (1, "mismatch", "mismatch")
    Ok(@sri.NoSupportedMetadata) =>
      (2, "no_supported_metadata", "no supported SRI metadata")
    Err(_) => (1, "below_minimum", "below minimum algorithm")
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
