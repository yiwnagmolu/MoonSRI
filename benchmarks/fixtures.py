"""Deterministic site snapshots for the review-release CLI."""

import base64
import hashlib
import io
import tarfile
import urllib.request
from dataclasses import dataclass
from pathlib import Path


def token(data, algorithm="sha384"):
    digest = hashlib.new(algorithm, data).digest()
    return algorithm + "-" + base64.b64encode(digest).decode("ascii")


def script(path, integrity):
    return f'<script src="/{path}" integrity="{integrity}"></script>'


def stylesheet(path, integrity):
    return f'<link rel="stylesheet" href="/{path}" integrity="{integrity}">'


def put(root, name, content):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content.encode("utf-8") if isinstance(content, str) else content)


@dataclass
class Shape:
    waves: list[int]
    edges: int
    cycle: int = 0


def docs(before, after, edit_every):
    js, css = b'console.log("docs");\n', b"table { width: 100% }\n"
    tags = script("assets/docs.js", token(js)) + stylesheet("assets/docs.css", token(css))
    for root in (before, after):
        put(root, "assets/docs.js", js)
        put(root, "assets/docs.css", css)
    for i in range(120):
        rows = "".join(
            f'<tr><th>Section {i}.{row}</th><td><a href="#item-{row}">Reference</a></td></tr>'
            for row in range(30)
        )
        body = f"<!doctype html><head>{tags}</head><h1>Guide {i}</h1><table>{rows}</table>"
        name = f"guide/chapter-{i:04}.html"
        put(before, name, body)
        put(after, name, body + ("<p>Updated</p>" if i % edit_every == 0 else ""))
    return Shape([120], 0)


def shared(before, after, length, pages, repeats):
    old = (b"//0123456789abc\n" * (length // 16 + 1))[:length]
    new = old[:-1] + b"!"
    old_sri, new_sri = token(old, "sha512"), token(new, "sha512")
    path = "assets/shared.js"
    for root, data, integrity in ((before, old, old_sri), (after, new, old_sri + " " + new_sri)):
        put(root, path, data)
        tags = script(path, integrity) * repeats
        for i in range(pages):
            put(root, f"p{i:04}.html", f"<!doctype html><head>{tags}</head><p>Page {i}</p>")
    return Shape([pages, 1], pages)


def wide(before, after):
    for i in range(256):
        path = f"assets/component-{i:04}.js"
        js = f'console.log("component {i}");\n'.encode()
        put(after, path, js)
        put(after, f"launch/p{i:04}.html", script(path, token(js)))
    return Shape([256, 256], 256)


def cycle(before, after):
    for root, data in ((before, b"old"), (after, b"new")):
        put(root, "assets/app.js", data)
        for i in range(384):
            body = f"<h1>Page {i}</h1>"
            if i == 383:
                body += script("assets/app.js", token(data))
            put(root, f"p{i:04}.html", body)
    return Shape([383], 2, 3)


def mixed(before, after):
    """Switch, retire and launch pages around two changing assets."""
    js, css = b'console.log("docs");\n', b"table { width: 100% }\n"
    old_banner, new_banner = b"banner v1\n", b"banner v2\n"
    launch = b'console.log("launch");\n'
    doc_tags = script("assets/docs.js", token(js)) + stylesheet("assets/docs.css", token(css))
    for root, banner in ((before, old_banner), (after, new_banner)):
        put(root, "assets/docs.js", js)
        put(root, "assets/docs.css", css)
        put(root, "assets/banner.js", banner)
    put(after, "assets/launch.js", launch)
    # Switched banner pages accept both versions, so they only wait for the
    # launch asset; retirement pages must switch before the banner is covered.
    both_banners = token(old_banner) + " " + token(new_banner)
    for i in range(40):
        name = f"guide/ch-{i:03}.html"
        put(before, name, f"<!doctype html><head>{doc_tags}{script('assets/banner.js', token(old_banner))}<h1>Old {i}</h1></body>")
        put(after, name, f"<!doctype html><head>{doc_tags}{script('assets/banner.js', both_banners)}<h1>New {i}</h1></body>")
    for i in range(40, 80):
        name = f"guide/ch-{i:03}.html"
        body = f"<!doctype html><head>{doc_tags}<h1>Guide {i}</h1></body>"
        put(before, name, body)
        put(after, name, body + "<p>Updated</p>")
    for i in range(80, 120):
        put(before, f"guide/ch-{i:03}.html", f"<!doctype html><head>{doc_tags}{script('assets/banner.js', token(old_banner))}<h1>Retired {i}</h1></body>")
    launch_tags = script("assets/launch.js", token(launch)) + doc_tags
    for i in range(40):
        put(after, f"launch/p-{i:03}.html", f"<!doctype html><head>{launch_tags}<h1>Launch {i}</h1></body>")
    # Eighty page actions precede the banner replacement (40 banner switches
    # plus 40 retirements) and the launch pages wait for their new asset.
    return Shape([121, 41], 120)


def mesh(before, after):
    """Sixty-four pages share eight assets, four of which change in place."""
    pages, count, replaced = 64, 8, 4
    old = [f'console.log("asset {i} v1");\n'.encode() for i in range(count)]
    new = [f'console.log("asset {i} v2");\n'.encode() for i in range(count)]
    for i in range(count):
        put(before, f"assets/a{i}.js", old[i])
        put(after, f"assets/a{i}.js", new[i] if i < replaced else old[i])
    for page in range(pages):
        name = f"mesh/p{page:03}.html"
        before_tags = "".join(
            script(f"assets/a{i}.js", token(old[i]) + " " + token(new[i]) if i < replaced else token(old[i]))
            for i in range(count)
        )
        after_tags = "".join(
            script(f"assets/a{i}.js", token(new[i] if i < replaced else old[i]))
            for i in range(count)
        )
        put(before, name, f"<!doctype html><head>{before_tags}<h1>{page}</h1></body>")
        put(after, name, f"<!doctype html><head>{after_tags}<h1>{page}</h1></body>")
    return Shape([replaced, pages], replaced * pages)


def deep(before, after):
    """A 255-node chain where every wave releases exactly one action."""
    n = 128
    old = [f'console.log("chain {i} old");\n'.encode() for i in range(n - 1)]
    new = [f'console.log("chain {i} new");\n'.encode() for i in range(n - 1)]
    for i in range(n - 1):
        put(before, f"assets/a{i}.js", old[i])
        put(after, f"assets/a{i}.js", new[i])
    for i in range(n):
        name = f"chain/p{i:03}.html"
        put(before, name, (script(f"assets/a{i - 1}.js", token(old[i - 1])) if i else "") + f"<h1>{i}</h1>")
        put(after, name, (script(f"assets/a{i}.js", token(new[i])) if i < n - 1 else "") + f"<h1>{i} v2</h1>")
    return Shape([1] * (2 * n - 1), 2 * (n - 1))


BOOTSTRAP = {
    "5.3.2": "sha512-D32nmNWiQHo94BKHLmOrdjlL05q1c8oxbtBphQFb9Z5to6eGRDCm0QgeaZ4zFBHzfg2++rqa2JkqCcxDy0sH0g==",
    "5.3.3": "sha512-8HLCdWgyoMguSO9o+aH+iuZ+aht+mzW0u3HIMzVu7Srrpv7EBBxTnrFlSCskwdY1+EOFQSm7uMJhNQHkdPcmjg==",
}


def bootstrap(before, after):
    for root, (version, expected) in zip((before, after), BOOTSTRAP.items()):
        url = f"https://registry.npmjs.org/bootstrap/-/bootstrap-{version}.tgz"
        with urllib.request.urlopen(url, timeout=60) as response:
            archive = response.read()
        if token(archive, "sha512") != expected:
            raise ValueError(f"Unexpected archive digest for {url}")
        tags = []
        with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as package:
            for name, tag in (("css/bootstrap.min.css", stylesheet), ("js/bootstrap.bundle.min.js", script)):
                data = package.extractfile(f"package/dist/{name}").read()
                path = f"assets/bootstrap-{version}/{name}"
                put(root, path, data)
                tags.append(tag(path, token(data)))
        for i in range(24):
            put(root, f"docs/page-{i:02}.html", f'<!doctype html><head>{"".join(tags)}</head><h1>Guide {i}</h1>')
    return Shape([2, 24], 48)


CASES = {
    "docs-10pct-edited": lambda before, after: docs(before, after, 10),
    "docs-100pct-edited": lambda before, after: docs(before, after, 1),
    "shared-2mib": lambda before, after: shared(before, after, 2 * 1024 * 1024, 12, 1),
    "repeat-64x64": lambda before, after: shared(before, after, 96, 64, 64),
    "wide-launch": wide,
    "late-cycle": cycle,
    "mixed-inventory": mixed,
    "dense-mesh": mesh,
    "deep-chain": deep,
    "bootstrap-upgrade": bootstrap,
}


def make_case(directory: Path, name):
    before, after = directory / "before", directory / "after"
    before.mkdir(parents=True)
    after.mkdir()
    shape = CASES[name](before, after)
    inputs = {}
    for root in (before, after):
        pages = sorted(p.relative_to(root).as_posix() for p in root.rglob("*.html"))
        put(directory, f"{root.name}.txt", "".join(p + "\n" for p in pages))
        files = [p for p in root.rglob("*") if p.is_file()]
        inputs[root.name] = {
            "pages": len(pages),
            "html_bytes": sum((root / p).stat().st_size for p in pages),
            "assets": len(files) - len(pages),
            "asset_bytes": sum(p.stat().st_size for p in files if p.suffix != ".html"),
        }
    return shape, inputs
