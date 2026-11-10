///|
priv struct BaselineCheck {
  declaration : String
  content : String
}

///|
fn read_audit_baseline(path : String) -> Map[String, String]? {
  guard read_manifest(path) is Some(entries) else { return None }
  let baseline = Map([])
  for asset, integrity in entries {
    guard is_portable_relative_path(asset) else {
      eprintln(
        "Invalid baseline asset path: " + Json::string(asset).stringify(),
      )
      return None
    }
    guard @sri.canonical_metadata(integrity) is Some(canonical) else {
      eprintln(
        "No supported SRI metadata in baseline for: " +
        Json::string(asset).stringify(),
      )
      return None
    }
    baseline[asset] = canonical
  }
  Some(baseline)
}

///|
fn AuditRun::check_baseline(
  self : AuditRun,
  path : String,
  declared : String?,
) -> (Int32, BaselineCheck?) {
  guard self.baseline is Some(entries) else { return (0, None) }
  guard entries.get(path) is Some(expected) else {
    return (1, Some({ declaration: "untracked", content: "not_checked", }))
  }
  let declaration = if declared == Some(expected) { "match" } else { "drift" }
  let (code, content) = self.verify_file(path, expected)
  let code = if declaration == "drift" && code == 0 { 1 } else { code }
  (code, Some({ declaration, content, }))
}
