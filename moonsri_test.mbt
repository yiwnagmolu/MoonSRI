///|
test "incremental hashing crosses block boundaries and supports snapshots" {
  let data = @utf8.encode("abc".repeat(100))
  for algorithm in [@moonsri.Sha256, @moonsri.Sha384, @moonsri.Sha512] {
    let hasher = @moonsri.Hasher::new(algorithm)
    hasher.update(data[:63])
    assert_eq(hasher.metadata(), @moonsri.generate(data[:63], algorithm))
    hasher.update(data[63:128])
    hasher.update(data[128:])
    assert_eq(hasher.metadata(), @moonsri.generate(data[:], algorithm))
    hasher.reset()
    assert_eq(hasher.metadata(), @moonsri.generate(data[:0], algorithm))
  }
}

///|
test "minimum algorithm rejects otherwise matching weak metadata" {
  let data = @utf8.encode("abc")
  let weak = @moonsri.generate(data[:], Sha256)
  let strong = @moonsri.generate(data[:], Sha512)
  assert_true(
    @moonsri.verify_bytes_at_least(data[:], weak, Sha384) is Err(Sha256),
  )
  assert_true(
    @moonsri.verify_bytes_at_least(data[:], weak + " " + strong, Sha512)
    is Ok(Match),
  )
  assert_true(
    @moonsri.verify_bytes_at_least(data[:], weak + " sha512-invalid", Sha384)
    is Ok(Mismatch),
  )
  assert_true(
    @moonsri.verify_bytes_at_least(data[:], "sha999-invalid", Sha384)
    is Ok(NoSupportedMetadata),
  )
}

///|
test "verification requests only the strongest needed token" {
  let data = @utf8.encode("abc")
  let sha512 = @moonsri.generate(data[:], Sha512)
  let requested : Array[@moonsri.Algorithm] = []
  let token_for = algorithm => {
    requested.push(algorithm)
    sha512
  }
  assert_true(
    @moonsri.verify_with_token("sha256-weak sha512-other " + sha512, token_for)
    is Ok(Match),
  )
  assert_true(
    @moonsri.verify_with_token("sha256-weak", token_for, minimum=Some(Sha384))
    is Err(Sha256),
  )
  assert_true(
    @moonsri.verify_with_token("sha999-other", token_for)
    is Ok(NoSupportedMetadata),
  )
  assert_eq(requested.length(), 1)
  assert_true(requested[0] is Sha512)
}

///|
/// Known SHA-2 vectors for the exact bytes "abc".
test "generates SHA-256, SHA-384 and SHA-512 SRI tokens" {
  let data = @utf8.encode("abc")
  assert_eq(
    @moonsri.generate(data[:], Sha256),
    "sha256-ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=",
  )
  assert_eq(
    @moonsri.generate(data[:], Sha384),
    "sha384-ywB1P0WjXou1oD1pmsZQBycsMqsO3tFjGotgWkP/W+2AhgcroefMI1i67KE0yCWn",
  )
  assert_eq(
    @moonsri.generate(data[:], Sha512),
    "sha512-3a81oZNherrMQXNJriBBMRLm+k6JqX6iCp7u5ktV05ohkpkqJ0/BqDa6PCOj/uu9RU1EI2Q86A4qmslPpUyknw==",
  )
}

///|
/// SHA-384 example from the W3C SRI specification, section 3.1.
test "matches the W3C SRI example" {
  let data = @utf8.encode("alert('Hello, world.');")
  assert_eq(
    @moonsri.generate(data[:], Sha384),
    "sha384-H8BRh8j48O9oYatfu5AZzq6A9RINhZO5H16dQZngK7T62em8MUt1FLm52t+eX6xO",
  )
}

///|
/// The strongest recognized family wins, even when a weaker digest matches.
test "does not fall back to a weaker digest" {
  let data = @utf8.encode("abc")
  let sha256 = @moonsri.generate(data[:], Sha256)
  let sha512 = @moonsri.generate(data[:], Sha512)
  assert_true(
    @moonsri.verify_bytes(data[:], sha256 + " sha512-deadbeef") is Mismatch,
  )
  assert_true(
    @moonsri.verify_bytes(data[:], "sha256-deadbeef " + sha512) is Match,
  )
}

///|
/// Two equally strong digests are alternatives.
test "accepts any matching digest of strongest strength" {
  let data = @utf8.encode("abc")
  let sha384 = @moonsri.generate(data[:], Sha384)
  assert_true(
    @moonsri.verify_bytes(data[:], "sha384-deadbeef " + sha384) is Match,
  )
  assert_true(@moonsri.verify_bytes(@utf8.encode("abd")[:], sha384) is Mismatch)
}

///|
/// Unsupported-only metadata must be visible to an offline checker.
test "reports empty and unsupported-only metadata" {
  let data = @utf8.encode("abc")
  assert_true(@moonsri.verify_bytes(data[:], "") is NoSupportedMetadata)
  assert_true(
    @moonsri.verify_bytes(data[:], "foo666-deadbeef") is NoSupportedMetadata,
  )
}

///|
/// A recognized but invalid digest still outranks a weaker valid digest.
test "recognized invalid digest does not fall back" {
  let data = @utf8.encode("abc")
  let sha256 = @moonsri.generate(data[:], Sha256)
  assert_true(
    @moonsri.verify_bytes(data[:], sha256 + " sha512-%%%") is Mismatch,
  )
  assert_true(@moonsri.verify_bytes(data[:], sha256 + " sha512") is Mismatch)
}

///|
test "parses only the digest field before trailing fields and options" {
  let parsed = @moonsri.parse_metadata(
    "sHa384-Digest-extra-fields?foo=a-b?bar=c sha512?foo=abc-def",
  )
  assert_eq(parsed.length(), 2)
  assert_true(parsed[0].algorithm is Sha384)
  assert_eq(parsed[0].digest, "Digest")
  assert_true(parsed[1].algorithm is Sha512)
  assert_eq(parsed[1].digest, "")
}

///|
test "metadata token boundaries account for Unicode characters" {
  let parsed = @moonsri.parse_metadata(
    " \tunknown-🙂 sha256-a🙂b\u{000c}SHA512-tail",
  )
  assert_eq(parsed.length(), 2)
  assert_true(parsed[0].algorithm is Sha256)
  assert_eq(parsed[0].digest, "a🙂b")
  assert_true(parsed[1].algorithm is Sha512)
  assert_eq(parsed[1].digest, "tail")
}

///|
test "canonical metadata compares effective digests across reordered declarations" {
  assert_eq(
    @moonsri.canonical_metadata(
      "sha256-weak SHA384-Z?opt=1 sha384-A sha384-Z sha999-x",
    ),
    Some("sha384-A sha384-Z"),
  )
  assert_eq(
    @moonsri.canonical_metadata("sha384-A sha384-a"),
    Some("sha384-A sha384-a"),
  )
  assert_eq(@moonsri.canonical_metadata("sha999-unknown"), None)
}

///|
/// SRI token matching is case-sensitive for the digest, not the algorithm name.
test "parses whitespace, unknown algorithms and options" {
  let data = @utf8.encode("abc")
  let sha256 = @moonsri.generate(data[:], Sha256)
  let upper_name = "SHA256-" + sha256.split("-").to_array()[1].to_owned()
  assert_true(
    @moonsri.verify_bytes(
      data[:],
      "\tfoo666-deadbeef\n" + upper_name + "?foo=bar\r",
    )
    is Match,
  )
  assert_true(
    @moonsri.verify_bytes(data[:], sha256.replace(old="ung", new="Ung"))
    is Mismatch,
  )
}

///|
/// Empty input has well-known SHA-2 digests; hashing zero bytes must not
/// accidentally yield the one-block padding state of a single character.
test "generates the empty-input digests for every algorithm" {
  let empty = @utf8.encode("")[:]
  assert_eq(
    @moonsri.generate(empty, Sha256),
    "sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=",
  )
  assert_eq(
    @moonsri.generate(empty, Sha384),
    "sha384-OLBgp1GsljhM2TJ+sbHjaiH9txEUvgdDTAzHv2P24donTt6/529l+9Ua0vFImLlb",
  )
  assert_eq(
    @moonsri.generate(empty, Sha512),
    "sha512-z4PhNX7vuL3xVChQ1m2AB9Yg5AULVxXcg/SpIdNs6c5H0NE8XYXysP+DGNKHfuwvY7kxvUdBeoGlODJ6+SfaPg==",
  )
  for algorithm in [@moonsri.Sha256, @moonsri.Sha384, @moonsri.Sha512] {
    assert_true(
      @moonsri.verify_bytes(empty, @moonsri.generate(empty, algorithm)) is Match,
    )
  }
}

///|
test "canonical metadata keeps a lone token verbatim and deduplicates sets" {
  assert_eq(@moonsri.canonical_metadata("sha256-Only"), Some("sha256-Only"))
  assert_eq(
    @moonsri.canonical_metadata("SHA512-B sha512-B sha512-A"),
    Some("sha512-A sha512-B"),
  )
  // The strongest family wins even when weaker digests differ.
  assert_eq(@moonsri.canonical_metadata("sha256-A sha384-B"), Some("sha384-B"))
  assert_eq(@moonsri.canonical_metadata(""), None)
}

///|
test "token providers returning foreign algorithms fail closed" {
  let data = @utf8.encode("abc")
  let sha384 = @moonsri.generate(data[:], Sha384)
  // A provider answering with the wrong algorithm cannot manufacture a match.
  assert_true(
    @moonsri.verify_with_token("sha512-x", _ => sha384) is Ok(Mismatch),
  )
  assert_true(
    @moonsri.verify_with_token("sha384-x", _ => "sha384") is Ok(Mismatch),
  )
  assert_true(
    @moonsri.verify_with_token("sha384-x", _ => sha384) is Ok(Mismatch),
  )
}

///|
test "verify_with_token reports minimum violations without hashing" {
  let data = @utf8.encode("abc")
  let requested : Array[@moonsri.Algorithm] = []
  assert_true(
    @moonsri.verify_with_token(
      "sha256-deadbeef",
      algorithm => {
        requested.push(algorithm)
        @moonsri.generate(data[:], algorithm)
      },
      minimum=Some(Sha512),
    )
    is Err(Sha256),
  )
  assert_eq(requested.length(), 0)
}
