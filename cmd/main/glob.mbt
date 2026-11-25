///|
fn has_glob_meta(pattern : String) -> Bool {
  pattern.contains_char('*') || pattern.contains_char('?')
}

///|
/// Reject glob patterns that cannot name portable relative assets. Segments
/// must be nonempty; `*` and `?` are the only metacharacters.
fn glob_pattern_error(pattern : String) -> String? {
  if pattern.is_empty() {
    return Some("Empty glob pattern")
  }
  let mut previous_slash = true
  for ch in pattern {
    if ch == '/' {
      if previous_slash {
        return Some("Glob patterns cannot contain empty path segments")
      }
      previous_slash = true
      continue
    }
    previous_slash = false
    if ch < ' ' || ch == '\u{007f}' || "\\<>:\"|".contains_char(ch) {
      return Some(
        "Glob patterns cannot contain " +
        Json::string(ch.to_string()).stringify(),
      )
    }
  }
  if previous_slash {
    return Some("Glob patterns cannot end with a path separator")
  }
  for segment in pattern.split("/") {
    if segment.has_suffix(".") || segment.has_suffix(" ") {
      return Some("Glob segments cannot end with a dot or a space")
    }
  }
  None
}

///|
/// Match a relative path against a glob pattern. A `**` segment spans any
/// number of whole segments, including none; inside one segment `*` matches
/// any run of characters and `?` matches exactly one. Everything else is
/// literal.
fn glob_match(pattern : String, path : String) -> Bool {
  let segments = pattern.split("/").collect()
  let candidates = path.split("/").collect()
  let path_length = candidates.length()
  // reachable[j] holds the pattern segment offset still matching the first
  // j path segments. Processing one segment at a time keeps `**` linear.
  let mut reachable = Array::make(path_length + 1, false)
  reachable[0] = true
  for segment in segments {
    let next = Array::make(path_length + 1, false)
    if segment == "**" {
      let mut spanning = false
      for j = 0; j <= path_length; j = j + 1 {
        if reachable[j] {
          spanning = true
        }
        next[j] = spanning
      }
    } else {
      for j = 0; j < path_length; j = j + 1 {
        if reachable[j] && glob_segment_matches(segment, candidates[j]) {
          next[j + 1] = true
        }
      }
    }
    reachable = next
  }
  reachable[path_length]
}

///|
fn glob_segment_matches(segment : StringView, text : StringView) -> Bool {
  // Dynamic programming over one path segment: dp[j] tracks whether the
  // remaining pattern chars can still match the remaining text chars.
  let pattern = segment.to_array()
  let target = text.to_array()
  let pattern_length = pattern.length()
  let text_length = target.length()
  // suffix[j] is true when pattern position i matches text[j..].
  let mut suffix = Array::make(text_length + 1, false)
  suffix[text_length] = true
  for i = pattern_length - 1; i >= 0; i = i - 1 {
    let star = pattern[i] == '*'
    let next = Array::make(text_length + 1, false)
    for j = text_length; j >= 0; j = j - 1 {
      next[j] = if star {
        suffix[j] || (j < text_length && next[j + 1])
      } else {
        j < text_length &&
        (pattern[i] == '?' || pattern[i] == target[j]) &&
        suffix[j + 1]
      }
    }
    suffix = next
  }
  suffix[0]
}

///|
/// List every file under `directory` as a relative path using `/`. A cyclic
/// or unreadable branch aborts the walk; nested trees deeper than 64 levels
/// are skipped to bound cyclic symlinks.
fn list_asset_files(directory : String) -> Array[String]? {
  // An empty prefix means the caller wants the current working directory;
  // keep a trailing slash so relative paths concatenate correctly.
  let base = if directory.is_empty() { "./" } else { directory }
  let files : Array[String] = []
  fn walk(prefix : String, depth : Int32) -> Bool {
    if depth > 64 {
      return true
    }
    let entries = @fs.read_dir(base + prefix) catch { _ => return false }
    for entry in entries {
      if entry == "." || entry == ".." {
        continue
      }
      let relative = prefix + entry
      let child = base + relative
      let is_file = @fs.is_file(child) catch { _ => return false }
      if is_file {
        files.push(relative)
      } else {
        let is_dir = @fs.is_dir(child) catch { _ => return false }
        if is_dir && !walk(relative + "/", depth + 1) {
          return false
        }
      }
    }
    true
  }
  if !walk("", 0) {
    return None
  }
  Some(files)
}
