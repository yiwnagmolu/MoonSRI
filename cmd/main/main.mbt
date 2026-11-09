///|
fn usage() -> Unit {
  println("Usage: moonsri generate <file> [sha256|sha384|sha512]")
  println("       moonsri check <file> <integrity-metadata>")
}

///|
fn run(args : Array[String]) -> Int32 {
  // The JS runner includes `node` in argv; the Wasm runner does not.
  let command_index = if args.length() > 1 &&
    (args[1] == "generate" || args[1] == "check") {
    1
  } else if args.length() > 2 && (args[2] == "generate" || args[2] == "check") {
    2
  } else {
    usage()
    return 2
  }
  let command = args[command_index]
  if (
      command == "generate" &&
      (args.length() < command_index + 2 || args.length() > command_index + 3)
    ) ||
    (command == "check" && args.length() != command_index + 3) {
    usage()
    return 2
  }
  let algorithm = if command == "generate" {
    if args.length() == command_index + 2 || args[command_index + 2] == "sha384" {
      @sri.Sha384
    } else {
      match args[command_index + 2] {
        "sha256" => @sri.Sha256
        "sha512" => @sri.Sha512
        _ => {
          usage()
          return 2
        }
      }
    }
  } else {
    @sri.Sha384
  }
  let path = args[command_index + 1]
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
  match @sri.verify_bytes(data[:], args[command_index + 2]) {
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
