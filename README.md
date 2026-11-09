# MoonSRI

MoonSRI 是一个用 MoonBit 编写的 [Subresource Integrity（SRI）](https://www.w3.org/TR/sri/) 元数据生成与校验工具。它对**本地文件的原始字节**计算 SHA-256、SHA-384 或 SHA-512 摘要，输出可用于 HTML `integrity` 属性的字符串，也能检查已有元数据是否与文件相符。

目前提供 MoonBit 库和命令行工具。适合在构建脚本、静态站点发布流程中为固定的 JavaScript / CSS 文件生成哈希，或在发布前检查文件是否被意外改动。

## 快速开始

安装 [MoonBit 工具链](https://www.moonbitlang.com/download/)，在仓库根目录运行：

```sh
moon test --target wasm
moon run cmd/main --target wasm -- generate examples/hello.js
```

示例输出（`examples/hello.js` 的结尾包含一个换行符）：

```text
sha384-uY+OtEjszwPe7jcYKI1KfAGMrLSMeFfhJc/DWf9ccFpWjjw1tKO9St/U0k2N8ONW
```

将该值写入 HTML 时，需确保部署的文件字节与计算时一致：

```html
<script src="/hello.js"
        integrity="sha384-uY+OtEjszwPe7jcYKI1KfAGMrLSMeFfhJc/DWf9ccFpWjjw1tKO9St/U0k2N8ONW"></script>
```

验证文件：

```sh
moon run cmd/main --target wasm -- check examples/hello.js 'sha384-uY+OtEjszwPe7jcYKI1KfAGMrLSMeFfhJc/DWf9ccFpWjjw1tKO9St/U0k2N8ONW'
```

输出为 `match`，退出码为 `0`。摘要不符时输出 `mismatch`、退出码为 `1`。元数据中没有任何受支持算法或发生用法、文件读取错误时，退出码为 `2`。

`generate` 默认使用 SHA-384，也可以显式指定 `sha256`、`sha384` 或 `sha512`：

```sh
moon run cmd/main --target wasm -- generate examples/hello.js sha512
```

也可以用逗号分隔算法，例如 `sha256,sha512`。输出会按指定顺序排列，多个摘要之间用空格分隔，可以一起填入同一个 `integrity` 属性。

在 Windows PowerShell 中，把示例里的单引号保留即可。也可用 `--target js` 运行，需有 Node.js。

## 批量生成与校验

在项目根目录列出要发布的资源，生成一份 JSON 清单：

```sh
moon run cmd/main --target wasm -- manifest examples/hello.js examples/style.css > integrity.json
moon run cmd/main --target wasm -- check-manifest integrity.json
```

在 Windows PowerShell 中，可以用 `| Set-Content -Encoding utf8 integrity.json` 替换第一条命令末尾的 `> integrity.json`。

清单是一个 UTF-8 JSON 对象，键是文件路径，值是 SRI 字符串。相对路径以**运行命令时的工作目录**为准。路径含空格时请加引号。默认算法是 SHA-384，可以在文件列表前加 `--algorithm sha512` 或 `--algorithm sha256,sha512`。文件名与选项同名时，在文件列表前加 `--`。

`check-manifest` 会报告各文件的结果。退出码 `0` 表示全部匹配，`1` 表示至少有一份摘要不匹配，`2` 表示清单无效、文件无法读取或元数据没有受支持的算法。若同时出现摘要不匹配和读取等错误，优先返回 `2`。请使用可信来源的清单，因为工具会按其中的路径读取本地文件。

脚本可以用 `--json` 获取结构化结果：

```sh
moon run cmd/main --target wasm -- check-manifest --json integrity.json
```

标准输出是一个 JSON 对象，键为清单中的文件路径，值为 `match`、`mismatch`、`read_error` 或 `no_supported_metadata`。清单有效时，即使有文件校验失败也会输出完整报告，退出码规则与默认模式相同。清单本身无法读取或解析时，诊断写入标准错误。

生成和校验都支持 `--root`。例如从 `dist` 生成清单，在发布目录 `staging` 校验同一份清单：

```sh
moon run cmd/main --target wasm -- manifest --root dist assets/app.js > integrity.json
moon run cmd/main --target wasm -- check-manifest --root staging integrity.json
```

清单键仍是 `assets/app.js`。使用 `--root` 时，资源路径必须是以 `/` 分隔的相对路径，路径段不能以点或空格结尾。指定的根目录用于拼接路径，操作系统仍会按正常规则解析符号链接。

## MoonBit 库

根包公开以下接口：

- `generate(data : BytesView, algorithm : Algorithm) -> String`：计算一个 SRI 元数据字符串。
- `parse_metadata(input : String) -> Array[Metadata]`：解析含多个哈希表达式的字符串，忽略未知算法。
- `verify_bytes(data : BytesView, input : String) -> Verdict`：仅检查元数据中最强的已识别算法；同一强度的多个摘要只要有一个匹配即可。

`Algorithm` 包含 `Sha256`、`Sha384`、`Sha512`；`Verdict` 包含 `Match`、`Mismatch`、`NoSupportedMetadata`。

如果应用分块读取资源，可以用 `Hasher::new(algorithm)` 创建增量计算器，按顺序调用 `update(chunk)`，最后用 `metadata()` 取得 SRI 字符串。中途读取摘要不会改变计算状态，调用 `reset()` 可用同一种算法开始计算下一个资源。

子包 `yiwnagmolu/moonsri/manifest` 提供 `parse` 和 `encode`。它负责检查 JSON 清单结构，返回路径到 SRI 字符串的映射，适合接入构建工具或自行决定如何读取资源。

## 范围与行为

- 依据 [W3C SRI 规范](https://www.w3.org/TR/sri/)处理算法优先级、多个摘要和保留的 `?options` 部分；目前没有已定义的 SRI 选项。
- 对已识别算法的摘要进行区分大小写的字符串比较。较强算法的摘要即使无效或不匹配，也不会退回较弱算法。
- 作为离线检查工具，`NoSupportedMetadata` 单独报告，不把空元数据默认为通过。浏览器规范在这种情况下返回通过；这个区别仅影响 MoonSRI 的离线检查结果。
- 不抓取 URL、不解析或改写 HTML、不模拟浏览器的 CORS、CSP、请求及响应处理。命令行只读取本地文件。
- 结果取决于精确字节；换行符或编码变化都会改变哈希。

## 开发

```sh
moon check --target wasm
moon test --target wasm
moon test --target js
moon info
moon fmt
```

测试包含 SHA-2 已知向量、最强算法选择、同等强度多摘要、未知算法及空元数据。CI 在 WebAssembly 和 JavaScript 目标运行测试及命令行示例。

本项目使用 [Apache-2.0 许可证](LICENSE)。
