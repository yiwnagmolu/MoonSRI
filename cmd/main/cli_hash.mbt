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
extern "js" fn hash_node(
  create : (String) -> NodeHash,
  algorithm : String,
  data : Bytes,
) -> String =
  #| (create, algorithm, data) => create(algorithm).update(data).digest("base64")

///|
#cfg(target="js")
fn generate_cli_token(data : Bytes, algorithm : @sri.Algorithm) -> String {
  let name = match algorithm {
    @sri.Sha256 => "sha256"
    @sri.Sha384 => "sha384"
    @sri.Sha512 => "sha512"
  }
  name + "-" + hash_node(create_node_hash, name, data)
}

///|
#cfg(not(target="js"))
fn generate_cli_token(data : Bytes, algorithm : @sri.Algorithm) -> String {
  @sri.generate(data[:], algorithm)
}
