///|
/// Validate an absolute HTTP(S) URL without requesting it.
/// Callers choose which URL forms are allowed before invoking this helper.
fn is_valid_http_url(input : StringView) -> Bool {
  @url.Url::try_parse(input) is Some(_)
}
