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

在 Windows PowerShell 中，把示例里的单引号保留即可。也可用 `--target js` 运行，需有 Node.js。

## MoonBit 库

根包公开以下接口：

- `generate(data : BytesView, algorithm : Algorithm) -> String`：计算一个 SRI 元数据字符串。
- `parse_metadata(input : String) -> Array[Metadata]`：解析含多个哈希表达式的字符串，忽略未知算法。
- `verify_bytes(data : BytesView, input : String) -> Verdict`：仅检查元数据中最强的已识别算法；同一强度的多个摘要只要有一个匹配即可。

`Algorithm` 包含 `Sha256`、`Sha384`、`Sha512`；`Verdict` 包含 `Match`、`Mismatch`、`NoSupportedMetadata`。

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
