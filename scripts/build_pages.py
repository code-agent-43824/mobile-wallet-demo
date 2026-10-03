#!/usr/bin/env python3
"""Render README.md + docs/*.md into public/index.html (stdlib only).

Reference: scripts/build_pages.py in coding-rules / product-vibecode
(simplified variant: single page, no sidebar — docs are few).
"""
import html as html_mod
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
PUBLIC = ROOT / "public"


def md_to_html(text: str) -> str:
    # escape everything first, then apply markdown rules
    text = html_mod.escape(text)
    text = re.sub(r"^###### (.*)$", r"<h6>\1</h6>", text, flags=re.M)
    text = re.sub(r"^##### (.*)$", r"<h5>\1</h5>", text, flags=re.M)
    text = re.sub(r"^#### (.*)$", r"<h4>\1</h4>", text, flags=re.M)
    text = re.sub(r"^### (.*)$", r"<h3>\1</h3>", text, flags=re.M)
    text = re.sub(r"^## (.*)$", r"<h2>\1</h2>", text, flags=re.M)
    text = re.sub(r"^# (.*)$", r"<h1>\1</h1>", text, flags=re.M)
    text = re.sub(r"```(.*?)```", r"<pre>\1</pre>", text, flags=re.S)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"^- (.*)$", r"<li>\1</li>", text, flags=re.M)
    text = re.sub(r"^\d+\. (.*)$", r"<li>\1</li>", text, flags=re.M)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    return text


def main() -> None:
    PUBLIC.mkdir(exist_ok=True)
    parts = [
        "<!DOCTYPE html><html lang=\"ru\"><head><meta charset=\"utf-8\">",
        "<title>mobile-wallet-demo — documentation</title>",
        "<style>body{font-family:sans-serif;max-width:900px;margin:2em auto;"
        "padding:0 1em;line-height:1.5}pre{background:#f4f4f4;padding:1em;"
        "overflow-x:auto}code{background:#f4f4f4;padding:0 0.3em}</style>",
        "</head><body>",
        "<nav><p><a href=\"#readme\">README</a>",
        " &middot; ",
        " <a href=\"#toc-docs\">docs/</a></p></nav>",
    ]
    readme = ROOT / "README.md"
    if readme.exists():
        parts.append('<h1 id="readme">README</h1>')
        parts.append(md_to_html(readme.read_text(encoding="utf-8")))

    docs_dir = ROOT / "docs"
    if docs_dir.exists():
        parts.append('<h2 id="toc-docs">docs/</h2><ul>')
        for md in sorted(docs_dir.glob("*.md")):
            parts.append(f'<li><a href="#doc-{md.stem}">{html_mod.escape(md.name)}</a></li>')
        parts.append("</ul>")
        for md in sorted(docs_dir.glob("*.md")):
            parts.append(f'<hr><div id="doc-{md.stem}">')
            parts.append(md_to_html(md.read_text(encoding="utf-8")))
            parts.append("</div>")

    parts.append("</body></html>")
    out = PUBLIC / "index.html"
    out.write_text("\n".join(parts), encoding="utf-8")
    print(f"Wrote {out} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
