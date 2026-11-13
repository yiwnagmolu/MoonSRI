///|
test "CLI hashing preserves binary input and algorithm order" {
  let data = b"\x00\r\n\x80\xff"
  assert_eq(
    generate_metadata(data, [@sri.Sha512, @sri.Sha256, @sri.Sha384]),
    "sha512-o/r5ceNJGsVfCV+Y6oy569g8zzbGuHT820RropX40fEdu7kr5RCHkR+2GmQBCictL8xQrFd2+1HAkxyeastXAg== " +
    "sha256-214xX/ijKMXPi6XnyOrhO355UNZpJkW5kZmAjO66doA= " +
    "sha384-WhOgNHXhec1MaV69+Ygej4ItGFxDKeJnceZxrhq/0sSbYe63WGRsEWfIUK3Drqqp",
  )
}
