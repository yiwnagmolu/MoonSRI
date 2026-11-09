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
