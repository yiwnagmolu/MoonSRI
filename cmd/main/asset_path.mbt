///|
fn is_portable_relative_path(path : String) -> Bool {
  path.split("/").all(is_portable_file_segment)
}

///|
fn is_portable_file_segment(segment : StringView) -> Bool {
  if segment.is_empty() || segment.has_suffix(".") || segment.has_suffix(" ") {
    return false
  }
  for ch in segment {
    if ch < ' ' || ch == '\u{007f}' || "/\\:<>\"|?*".contains_char(ch) {
      return false
    }
  }
  // Windows treats these basenames as devices even with a file extension.
  let stem = match segment.split_once(".") {
    Some((stem, _)) => stem
    None => segment
  }
  let name = stem.trim_end(chars=" ").to_lower()
  match name {
    "con" | "prn" | "aux" | "nul" | "conin$" | "conout$" => false
    _ => {
      if name.has_prefix("com") || name.has_prefix("lpt") {
        let suffix = name.exact_view(start=3)
        return !(suffix.char_length() == 1 && "123456789¹²³".contains(suffix))
      }
      true
    }
  }
}
