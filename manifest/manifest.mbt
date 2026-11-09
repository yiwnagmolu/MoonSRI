///|
pub(all) suberror ManifestError {
  InvalidJson(String)
  EmptyOrNonObject
  InvalidPath(String)
  ExpectedString(String)
}

///|
pub fn ManifestError::message(self : ManifestError) -> String {
  match self {
    InvalidJson(detail) => "Invalid manifest JSON: " + detail
    EmptyOrNonObject => "Manifest must be a non-empty JSON object"
    InvalidPath(path) => "Invalid asset path: " + Json::string(path).stringify()
    ExpectedString(path) =>
      "Expected a string for asset: " + Json::string(path).stringify()
  }
}

///|
pub fn is_asset_path(path : String) -> Bool {
  !path.is_empty() && !path.contains_char('\u{0000}')
}

///|
/// Parse the path-to-metadata format without reading any of the asset paths.
pub fn parse(source : String) -> Map[String, String] raise ManifestError {
  let parsed = @json.parse(source, reject_duplicate_keys=true) catch {
    error => raise InvalidJson(error.to_string())
  }
  guard parsed is Object(entries) && !entries.is_empty() else {
    raise EmptyOrNonObject
  }
  let assets : Map[String, String] = Map([])
  for path, value in entries {
    guard is_asset_path(path) else { raise InvalidPath(path) }
    guard value is String(metadata) else { raise ExpectedString(path) }
    assets[path] = metadata
  }
  assets
}

///|
/// Encode a nonempty path-to-metadata map as JSON.
pub fn encode(assets : Map[String, String]) -> String raise ManifestError {
  guard !assets.is_empty() else { raise EmptyOrNonObject }
  let entries : Map[String, Json] = Map([])
  for path, metadata in assets {
    guard is_asset_path(path) else { raise InvalidPath(path) }
    entries[path] = Json::string(metadata)
  }
  Json::object(entries).stringify(indent=2)
}
