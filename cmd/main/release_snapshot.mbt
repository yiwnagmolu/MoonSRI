///|
priv struct ReleaseRef {
  path : String
  integrity : String
}

///|
/// Collect local references in DOM order. External URLs do not participate
/// in the local release plan.
fn load_release_pages(
  prefix : String,
  pages : ArrayView[String],
) -> Result[Map[String, Array[ReleaseRef]], String] {
  let result : Map[String, Array[ReleaseRef]] = Map([])
  for page in pages {
    let (directory, document) = match read_audit_page(prefix, page) {
      Ok(value) => value
      Err(reason) =>
        return Err("page " + Json::string(page).stringify() + ": " + reason)
    }
    let refs : Array[ReleaseRef] = []
    for reference in document.references {
      let path = match resolve_audit_path(directory, reference.url) {
        Local(path) => path
        External => continue
        _ =>
          return Err(
            "page " +
            Json::string(page).stringify() +
            ": invalid URL " +
            Json::string(reference.url).stringify(),
          )
      }
      let integrity = reference.integrity.unwrap_or("")
      if integrity.trim(chars=" \t\n\r\u{000c}").is_empty() {
        return Err(
          "page " +
          Json::string(page).stringify() +
          ": missing integrity for " +
          Json::string(path).stringify(),
        )
      }
      if @sri.canonical_metadata(integrity) is None {
        return Err(
          "page " +
          Json::string(page).stringify() +
          ": no supported integrity for " +
          Json::string(path).stringify(),
        )
      }
      refs.push({ path, integrity, })
    }
    result[page] = refs
  }
  Ok(result)
}

///|
priv struct ReleaseFiles {
  prefix : String
  tokens : Map[(String, @sri.Algorithm), String]
}

///|
fn ReleaseFiles::token(
  self : ReleaseFiles,
  path : String,
  algorithm : @sri.Algorithm,
) -> String raise {
  let key = (path, algorithm)
  if self.tokens.get(key) is Some(token) {
    return token
  }
  let token = generate_file_metadata(self.prefix + path, [algorithm])
  self.tokens[key] = token
  token
}

///|
fn ReleaseFiles::matches(
  self : ReleaseFiles,
  reference : ReleaseRef,
) -> Bool raise {
  let verdict = @sri.verify_with_token(reference.integrity, algorithm => {
    self.token(reference.path, algorithm)
  })
  verdict is Ok(Match)
}

///|
fn ReleaseFiles::same_asset(
  before : ReleaseFiles,
  after : ReleaseFiles,
  path : String,
) -> Bool raise {
  let key = (path, @sri.Sha512)
  if before.tokens.get(key) is Some(previous) &&
    after.tokens.get(key) is Some(current) {
    return previous == current
  }
  before.token(path, @sri.Sha384) == after.token(path, @sri.Sha384)
}

///|
/// A retained file cannot also be a directory for a different release path.
fn release_path_conflict(
  paths : Array[String],
  all_paths : Set[String],
) -> (String, String)? {
  for path in paths {
    let mut child = path
    while child.rev_split_once("/") is Some((parent, _)) {
      let parent = parent.to_owned()
      if all_paths.contains(parent) {
        return Some((parent, path))
      }
      child = parent
    }
  }
  None
}

///|
/// Collect verified endpoint declarations and evidence for cross-version
/// compatibility. A newly referenced path is treated as an unpublished asset.
fn collect_release_inputs(
  before_root : String,
  after_root : String,
  before_pages : ArrayView[String],
  after_pages : ArrayView[String],
) -> Result[
  (Array[@rollout.Page], Map[String, @rollout.AssetChange], Array[String]),
  String,
] {
  let before = match load_release_pages(before_root, before_pages) {
    Ok(value) => value
    Err(reason) => return Err("before " + reason)
  }
  let after = match load_release_pages(after_root, after_pages) {
    Ok(value) => value
    Err(reason) => return Err("after " + reason)
  }
  let before_files : ReleaseFiles = { prefix: before_root, tokens: Map([]), }
  let after_files : ReleaseFiles = { prefix: after_root, tokens: Map([]), }
  let before_paths : Set[String] = Set([])
  let after_paths : Set[String] = Set([])
  let page_paths : Set[String] = Set([])
  let all_paths : Set[String] = Set([])
  let ordered_paths : Array[String] = []
  for page in before_pages {
    page_paths.add(page)
  }
  for page in after_pages {
    page_paths.add(page)
  }
  let pages = page_paths.iter().to_array()
  pages.sort_by((left, right) => left.lexical_compare(right))
  for page in pages {
    all_paths.add(page)
    ordered_paths.push(page)
  }
  for page in pages {
    let before_refs = before.get(page).unwrap_or([])
    let after_refs = after.get(page).unwrap_or([])
    for reference in before_refs {
      if page_paths.contains(reference.path) {
        return Err(
          "page " +
          Json::string(page).stringify() +
          ": resource is also an input page " +
          Json::string(reference.path).stringify(),
        )
      }
      let matches = before_files.matches(reference) catch {
        _ =>
          return Err(
            "before page " +
            Json::string(page).stringify() +
            ": cannot read asset " +
            Json::string(reference.path).stringify(),
          )
      }
      if !matches {
        return Err(
          "before page " +
          Json::string(page).stringify() +
          ": integrity mismatch for " +
          Json::string(reference.path).stringify(),
        )
      }
      before_paths.add(reference.path)
      if !all_paths.contains(reference.path) {
        all_paths.add(reference.path)
        ordered_paths.push(reference.path)
      }
    }
    for reference in after_refs {
      if page_paths.contains(reference.path) {
        return Err(
          "page " +
          Json::string(page).stringify() +
          ": resource is also an input page " +
          Json::string(reference.path).stringify(),
        )
      }
      let matches = after_files.matches(reference) catch {
        _ =>
          return Err(
            "after page " +
            Json::string(page).stringify() +
            ": cannot read asset " +
            Json::string(reference.path).stringify(),
          )
      }
      if !matches {
        return Err(
          "after page " +
          Json::string(page).stringify() +
          ": integrity mismatch for " +
          Json::string(reference.path).stringify(),
        )
      }
      after_paths.add(reference.path)
      if !all_paths.contains(reference.path) {
        all_paths.add(reference.path)
        ordered_paths.push(reference.path)
      }
    }
  }
  if release_path_conflict(ordered_paths, all_paths) is Some((parent, child)) {
    return Err(
      "file/directory path conflict: " +
      Json::string(parent).stringify() +
      " and " +
      Json::string(child).stringify(),
    )
  }
  let assets : Map[String, @rollout.AssetChange] = Map([])
  for path in ordered_paths {
    if !after_paths.contains(path) {
      continue
    }
    if !before_paths.contains(path) {
      assets[path] = @rollout.Publish
      continue
    }
    let unchanged = before_files.same_asset(after_files, path) catch {
      _ =>
        return Err(
          "cannot compare release asset " + Json::string(path).stringify(),
        )
    }
    if !unchanged {
      assets[path] = @rollout.Replace
    }
  }
  let result : Array[@rollout.Page] = []
  for page in pages {
    let before_refs = before.get(page).unwrap_or([])
    let after_refs = after.get(page).unwrap_or([])
    let before_cross : Map[String, Bool] = Map([])
    let after_cross : Map[String, Bool] = Map([])
    for reference in before_refs {
      let compatible = if assets.get(reference.path) is Some(@rollout.Replace) {
        after_files.matches(reference) catch {
          _ =>
            return Err(
              "after asset cannot be read for page " +
              Json::string(page).stringify() +
              ": " +
              Json::string(reference.path).stringify(),
            )
        }
      } else {
        true
      }
      before_cross[reference.path] = before_cross
        .get(reference.path)
        .unwrap_or(true) &&
        compatible
    }
    for reference in after_refs {
      let compatible = match assets.get(reference.path) {
        Some(@rollout.Replace) =>
          before_files.matches(reference) catch {
            _ =>
              return Err(
                "before asset cannot be read for page " +
                Json::string(page).stringify() +
                ": " +
                Json::string(reference.path).stringify(),
              )
          }
        Some(@rollout.Publish) => false
        None => true
      }
      after_cross[reference.path] = after_cross
        .get(reference.path)
        .unwrap_or(true) &&
        compatible
    }
    result.push({ path: page, before: before_cross, after: after_cross, })
  }
  let retained : Array[String] = []
  for path in before_paths {
    if !after_paths.contains(path) {
      retained.push(path)
    }
  }
  retained.sort_by((left, right) => left.lexical_compare(right))
  Ok((result, assets, retained))
}
