# 两页静态站点的 SRI 发布顺序

这是一个可复现的合成案例。门店目录有首页 `index.html` 和营业时间页 `hours/index.html`，两页共同引用 `assets/app.js` 和 `assets/site.css`。新版更新共享脚本，并在首页增加 `assets/banner.js`。资源均为本地文件，HTML 中的 `integrity` 是对应文件的 SHA-384 摘要。

三个目录分别表示部署前后的完整快照：

| 快照 | 两个页面引用的共享脚本 | 文件状态 |
| --- | --- | --- |
| `before` | `assets/app.js` 的旧摘要 | 旧 JS 和共享 CSS |
| `overwrite` | 同一路径 `assets/app.js` 的新摘要 | JS 被覆盖，新增 `banner.js`，CSS 未变 |
| `versioned` | 新路径 `assets/app.v2.js` 的新摘要 | 保留旧 JS，新增 `app.v2.js` 和 `banner.js`，CSS 未变 |

两个新快照各自的页面和资源都能通过 SRI 校验。比较关注它们在逐文件发布时可能出现的中间状态。检查假设每个文件的发布动作独立生效，且旧、新页面和资源可能混用。

## 先检查快照

在仓库根目录依次运行，三条命令都应返回 `0`：

```sh
moon run cmd/main --target wasm -- audit-html --root examples/rollout/before --json index.html hours/index.html
moon run cmd/main --target wasm -- audit-html --root examples/rollout/overwrite --json index.html hours/index.html
moon run cmd/main --target wasm -- audit-html --root examples/rollout/versioned --json index.html hours/index.html
```

JSON 报告中每个页面的 `status` 应为 `ok`，各本地资源的 `status` 应为 `match`。

## 审查原地覆盖

```sh
moon run cmd/main --target wasm -- review-release --before-root examples/rollout/before --after-root examples/rollout/overwrite --json index.html hours/index.html
```

预期返回 `1`，报告 `status` 为 `blocked`。两个页面的旧声明都需要旧 `app.js`，所以都要在替换脚本之前切换；两个页面的新声明又都需要新 `app.js`，所以替换脚本必须在页面切换之前完成。这些先后要求形成循环。新增的 `banner.js` 与该循环无关，可作为独立的前置发布动作，但它不能解除共享脚本的循环。

## 审查版本化路径

```sh
moon run cmd/main --target wasm -- review-release --before-root examples/rollout/before --after-root examples/rollout/versioned --json index.html hours/index.html
```

预期返回 `0`，报告 `status` 为 `safe`。`waves` 给出满足依赖的发布批次：先发布 `assets/app.v2.js` 和 `assets/banner.js`，再切换引用它们的页面。营业时间页不依赖 `banner.js`，因此报告可以将没有依赖关系的动作放在同一批次。保留旧 `assets/app.js`，使仍在使用旧页面的访问者能继续读取旧脚本。

报告的 `constraints` 描述动作的先后要求，`cycle` 在有循环时列出形成循环的动作。参数或快照读取有误时命令返回 `2`。Windows PowerShell 中可在运行命令后查看 `$LASTEXITCODE`。

本案例只推导静态 HTML、声明和本地资源的 SRI 发布顺序。实际发布仍需处理缓存有效期、CDN 传播与旧资源保留期限等环境因素。
