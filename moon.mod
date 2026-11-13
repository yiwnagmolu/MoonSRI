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

version = "0.5.2"

readme = "README.md"

repository = "https://github.com/yiwnagmolu/MoonSRI"

license = "Apache-2.0"

keywords = [ "sri", "integrity", "sha2", "subresource-integrity" ]

preferred_target = "wasm"

description = "MoonBit Subresource Integrity toolkit with HTML audits, trusted baselines, and release-to-release HTML reference diffs"

import {
  "moonbitstack/mooncrypt@0.4.13",
  "moonbitlang/x@0.5.7",
  "moonbit-community/html@0.2.4",
  "tonyfettes/url@0.3.5",
}
