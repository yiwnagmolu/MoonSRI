///|
fn usage() -> Unit {
  println("Usage: moonsri generate <file> [sha256|sha384|sha512]")
  println("       moonsri check <file> <integrity-metadata>")
  println(
    "       moonsri manifest [--algorithm sha256|sha384|sha512] [--] <file>...",
  )
  println("       moonsri check-manifest <manifest.json>")
}

///|
fn is_command(arg : String) -> Bool {
  match arg {
    "generate" | "check" | "manifest" | "check-manifest" => true
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
    "check-manifest" =>
      if operands.length() == 1 {
        return check_manifest(operands[0])
      } else {
        usage()
        return 2
      }
    _ => ()
  }
  if (command == "generate" && (operands.length() < 1 || operands.length() > 2)) ||
    (command == "check" && operands.length() != 2) {
    usage()
    return 2
  }
  let algorithm = if command == "generate" {
    if operands.length() == 1 {
      @sri.Sha384
    } else {
      match parse_algorithm(operands[1]) {
        Some(algorithm) => algorithm
        None => {
          usage()
          return 2
        }
      }
    }
  } else {
    @sri.Sha384
  }
  let path = operands[0]
  let data = @fs.read_file_to_bytes(path) catch {
    _ => {
      println("Cannot read file: " + path)
      return 2
    }
  }
  if command == "generate" {
    println(@sri.generate(data[:], algorithm))
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
fn main {
  @sys.exit(run(@env.args()))
}
