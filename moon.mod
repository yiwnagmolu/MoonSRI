// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "yiwnagmolu/moonsri"

version = "0.3.1"

readme = "README.md"

repository = "https://github.com/yiwnagmolu/MoonSRI"

license = "Apache-2.0"

keywords = [ "sri", "integrity", "sha2", "subresource-integrity" ]

preferred_target = "wasm"

description = "Generate and verify Subresource Integrity metadata in MoonBit"

import {
  "moonbitstack/mooncrypt@0.4.13",
  "moonbitlang/x@0.5.7",
  "moonbit-community/html@0.2.4",
}
