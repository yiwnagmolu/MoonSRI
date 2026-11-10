///|
pub(all) enum ResourceKind {
  Script
  Stylesheet
}

///|
pub(all) struct Reference {
  kind : ResourceKind
  url : String
  integrity : String?
}

///|
pub(all) struct Document {
  references : Array[Reference]
  base_href : String?
}

///|
/// Collect static script and stylesheet references from HTML in DOM order.
/// Templates, noscript content, and disabled stylesheets are skipped.
pub fn scan(source : String) -> Document {
  let doc = @html5.parse_with_scripting(source)
  let references = []
  let mut base_href = None
  let pending = [doc.document_element]
  while pending.pop() is Some(node) {
    if doc.is_html_element(node, "template") ||
      doc.is_html_element(node, "noscript") {
      continue
    }
    if base_href is None && doc.is_html_element(node, "base") {
      base_href = doc.get_attribute(node, "href")
    }
    if doc.is_html_element(node, "script") && is_script(doc, node) {
      if doc.get_attribute(node, "src") is Some(url) {
        references.push({
          kind: Script,
          url,
          integrity: doc.get_attribute(node, "integrity"),
        })
      }
    } else if doc.is_html_element(node, "link") {
      if doc.get_attribute(node, "rel") is Some(rel) &&
        has_stylesheet_rel(rel) &&
        doc.get_attribute(node, "disabled") is None &&
        doc.get_attribute(node, "href") is Some(url) {
        references.push({
          kind: Stylesheet,
          url,
          integrity: doc.get_attribute(node, "integrity"),
        })
      }
    }
    let children = doc.get_children(node)
    for index = children.length() - 1; index >= 0; index = index - 1 {
      pending.push(children[index])
    }
  }
  { references, base_href, }
}

///|
fn is_script(doc : @html5.Document, node : Int32) -> Bool {
  let type_string = match doc.get_attribute(node, "type") {
    Some("") => return true
    Some(value) if value.equal_ignore_ascii_case("module") => return true
    Some(value) => value.trim(chars=" \t\n\r\u{000c}").to_owned()
    None =>
      match doc.get_attribute(node, "language") {
        None | Some("") => return true
        Some(language) => "text/" + language
      }
  }
  // JavaScript MIME type essence matches from the WHATWG MIME Sniffing standard.
  match type_string.to_lower() {
    "application/ecmascript"
    | "application/javascript"
    | "application/x-ecmascript"
    | "application/x-javascript"
    | "text/ecmascript"
    | "text/javascript"
    | "text/javascript1.0"
    | "text/javascript1.1"
    | "text/javascript1.2"
    | "text/javascript1.3"
    | "text/javascript1.4"
    | "text/javascript1.5"
    | "text/jscript"
    | "text/livescript"
    | "text/x-ecmascript"
    | "text/x-javascript" => true
    _ => false
  }
}

///|
fn has_stylesheet_rel(rel : String) -> Bool {
  let normalized = StringBuilder()
  for ch in rel {
    normalized.write_char(
      if ch == '\t' || ch == '\n' || ch == '\r' || ch == '\u{000c}' {
        ' '
      } else {
        ch
      },
    )
  }
  normalized
  .to_string()
  .split(" ")
  .any(token => token.equal_ignore_ascii_case("stylesheet"))
}
