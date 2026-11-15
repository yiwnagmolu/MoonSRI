///|
#cfg(target="js")
#external
priv type NodeHash

///|
#cfg(target="js")
#module("node:crypto")
extern "js" fn create_node_hash(name : String) -> NodeHash = "createHash"

///|
#cfg(target="js")
#module("node:fs")
extern "js" fn open_node_file(path : String, flags : String) -> Int32 = "openSync"

///|
#cfg(target="js")
#module("node:fs")
extern "js" fn read_node_file(fd : Int32, buffer : Bytes) -> Int32 = "readSync"

///|
#cfg(target="js")
#module("node:fs")
extern "js" fn close_node_file(fd : Int32) -> Unit = "closeSync"

///|
#cfg(target="js")
extern "js" fn hash_node_file(
  create : (String) -> NodeHash,
  open : (String, String) -> Int32,
  read : (Int32, Bytes) -> Int32,
  close : (Int32) -> Unit,
  path : String,
  names : FixedArray[String],
) -> String =
  #| (create, open, read, close, path, names) => {
  #|   try {
  #|     const fd = open(path, "r");
  #|     try {
  #|       const hashes = names.map(name => create(name));
  #|       const buffer = Buffer.allocUnsafe(64 * 1024);
  #|       for (let n = read(fd, buffer); n !== 0; n = read(fd, buffer)) {
  #|         const chunk = n === buffer.length ? buffer : buffer.subarray(0, n);
  #|         for (const hash of hashes) hash.update(chunk);
  #|       }
  #|       return ":" + hashes.map((hash, i) => names[i] + "-" + hash.digest("base64")).join(" ");
  #|     } finally {
  #|       close(fd);
  #|     }
  #|   } catch {
  #|     return "";
  #|   }
  #| }

///|
#cfg(target="js")
fn generate_file_metadata(
  path : String,
  algorithms : Array[@sri.Algorithm],
) -> String raise {
  let names = FixedArray::makei(algorithms.length(), index => {
    match algorithms[index] {
      @sri.Sha256 => "sha256"
      @sri.Sha384 => "sha384"
      @sri.Sha512 => "sha512"
    }
  })
  let result = hash_node_file(
    create_node_hash, open_node_file, read_node_file, close_node_file, path, names,
  )
  // Prefix successful reads so an empty algorithm list has a distinct result.
  guard result.strip_prefix(":") is Some(metadata) else {
    raise @fs.IOError("Cannot read file")
  }
  metadata.to_owned()
}

///|
#cfg(not(target="js"))
fn generate_file_metadata(
  path : String,
  algorithms : Array[@sri.Algorithm],
) -> String raise {
  let data = @fs.read_file_to_bytes(path)
  algorithms.map(algorithm => @sri.generate(data[:], algorithm)).join(" ")
}
