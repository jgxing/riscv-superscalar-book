#!/usr/bin/env python3
"""把教材 Markdown 转成 GitHub Pages 静态阅读页（首页 + 各章独立页面）。"""
import html
import json
import pathlib
import posixpath
import re
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
CFG = json.loads((ROOT / 'site_config.json').read_text(encoding='utf-8'))

CSS = """
:root { --red: #C8102E; --ink: #1f2328; --muted: #6b7280; --line: #e5e7eb; --bg: #ffffff; --soft: #faf9f7; }
* { box-sizing: border-box; }
html { scroll-behavior: smooth; }
body { margin: 0; color: var(--ink); background: var(--bg); line-height: 1.8;
       font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Microsoft YaHei", "PingFang SC", sans-serif; }
a { color: var(--red); text-decoration: none; }
a:hover { text-decoration: underline; }
.topbar { position: sticky; top: 0; z-index: 20; background: rgba(255,255,255,.97);
          border-bottom: 2px solid var(--red); padding: 10px 24px;
          display: flex; align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap; }
.topbar .brand { font-weight: 700; color: var(--ink); font-size: 15px; }
.topbar nav { display: flex; gap: 16px; font-size: 13px; align-items: center; flex-wrap: wrap; }
.topbar nav a { color: #374151; }
.topbar nav a:hover { color: var(--red); }
.wrap { max-width: 900px; margin: 0 auto; padding: 32px 22px 90px; }
.hero { display: flex; gap: 36px; align-items: flex-start; flex-wrap: wrap; margin: 18px 0 46px; }
.hero .cover { width: 232px; max-width: 100%; border: 1px solid var(--line);
               box-shadow: 0 8px 28px rgba(0,0,0,.12); border-radius: 2px; }
.hero .info { flex: 1 1 360px; }
.series { color: var(--red); font-size: 13px; letter-spacing: 2px; margin: 4px 0 10px; }
.hero h1 { font-size: 32px; line-height: 1.3; margin: 0 0 6px; }
.hero .subtitle { font-size: 21px; color: var(--red); margin: 0 0 18px; }
.byline { color: var(--muted); font-size: 14px; margin: 0 0 20px; }
.intro { color: #374151; font-size: 15px; margin: 0 0 24px; }
.btn { display: inline-block; padding: 9px 20px; background: var(--red); color: #fff;
       border-radius: 4px; font-size: 14px; margin-right: 10px; }
.btn:hover { background: #a50e26; text-decoration: none; }
.btn.ghost { background: #fff; color: var(--red); border: 1px solid var(--red); }
.btn.ghost:hover { background: #fdf2f4; }
.toc-group { margin: 30px 0; }
.toc-group h2 { font-size: 18px; color: var(--ink); border-bottom: 2px solid var(--line);
                padding-bottom: 8px; margin: 0 0 12px; }
ol.toc-list { list-style: none; padding: 0; margin: 0; counter-reset: item; }
ol.toc-list li { border-bottom: 1px dashed var(--line); padding: 7px 2px; font-size: 15px; }
ol.toc-list li a { color: var(--ink); }
ol.toc-list li a:hover { color: var(--red); }
.article h1 { font-size: 28px; color: var(--red); border-bottom: 3px solid var(--red);
              padding-bottom: 10px; margin: 0 0 28px; line-height: 1.4; }
.article h2 { font-size: 21px; margin: 38px 0 12px; padding-left: 10px; border-left: 4px solid var(--red); }
.article h3 { font-size: 17px; margin: 26px 0 8px; }
.article p { text-align: justify; margin: 12px 0; }
.article img { max-width: 100%; height: auto; display: block; margin: 22px auto 6px; }
.article blockquote { border-left: 3px solid var(--line); background: var(--soft);
                      margin: 16px 0; padding: 10px 16px; color: #4b5563; }
.article pre { background: #f6f6f4; border-left: 3px solid var(--red); padding: 14px 16px;
               border-radius: 0 4px 4px 0; overflow-x: auto; font-size: 13px; line-height: 1.6; }
.article code { font-family: Consolas, "Courier New", monospace; background: #f2f2f0;
                padding: 1px 4px; border-radius: 3px; font-size: .92em; }
.article pre code { background: none; padding: 0; }
.article table { border-collapse: collapse; width: 100%; margin: 18px 0; font-size: 14px; }
.article th, .article td { border: 1px solid var(--line); padding: 7px 10px; text-align: left; vertical-align: top; }
.article th { background: var(--soft); font-weight: 600; }
.pagenav { display: flex; justify-content: space-between; gap: 12px; flex-wrap: wrap;
           border-top: 1px solid var(--line); margin-top: 54px; padding-top: 18px; font-size: 14px; }
footer { text-align: center; color: var(--muted); font-size: 12px; padding: 22px 0 40px; }
@media (max-width: 640px) { .hero h1 { font-size: 26px; } .wrap { padding: 20px 16px 60px; } }
"""

def title_from_md(path: pathlib.Path) -> str:
    for line in path.read_text(encoding='utf-8').splitlines():
        if line.startswith('# '):
            return re.sub(r'[*_`]', '', line[2:]).strip()
    return path.stem

def pandoc_body(path: pathlib.Path, img_prefix: str) -> str:
    tmp = pathlib.Path(tempfile.gettempdir()) / 'riscv_site_tmp.html'
    subprocess.run(['pandoc', '-f', 'markdown', '-t', 'html5', '--wrap=none',
                    '--no-highlight', str(path), '-o', str(tmp)], check=True)
    body = tmp.read_text(encoding='utf-8')
    # 根目录页面用 figures/，chapters/ 下的页面沿用 ../figures/
    return body.replace('](../figures/', '](' + img_prefix + 'figures/')

def rel(target: str, current: str) -> str:
    return posixpath.relpath(target, posixpath.dirname(current) or '.')

def topbar(current: str, prev, nxt) -> str:
    home = rel('index.html', current)
    parts = ['<a class="brand" href="%s">%s</a>' % (home, html.escape(CFG['title']))]
    nav = ['<a href="%s">目录</a>' % home]
    if prev:
        nav.append('<a href="%s">← %s</a>' % (rel(prev['out'], current), html.escape(prev['short'])))
    if nxt:
        nav.append('<a href="%s">%s →</a>' % (rel(nxt['out'], current), html.escape(nxt['short'])))
    nav.append('<a href="%s">代码仓库</a>' % html.escape(CFG['repo']))
    parts.append('<nav>%s</nav>' % ''.join(nav))
    return '<header class="topbar">%s</header>' % ''.join(parts)

def shell(current: str, title: str, body: str, prev, nxt) -> str:
    return """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>%s</title>
<style>%s</style>
</head>
<body>
%s
<main class="wrap">%s</main>
<footer>%s　·　%s</footer>
</body>
</html>
""" % (html.escape(title), CSS, topbar(current, prev, nxt), body,
       html.escape(CFG['affiliation']), html.escape(CFG['author']))

def build_entries():
    entries = []
    for item in CFG['front']:
        src = ROOT / item['src']
        entries.append({'label': title_from_md(src), 'short': item.get('label', title_from_md(src)),
                        'src': src, 'out': item['out'], 'group': '前言'})
    cdir = ROOT / CFG['chapters']['dir']
    for i, src in enumerate(sorted(cdir.glob(CFG['chapters']['pattern'])), 1):
        label = title_from_md(src)
        out = '%s/%s%02d.html' % (CFG['chapters']['dir'], CFG['chapters']['out_prefix'], i)
        entries.append({'label': label, 'short': '第 %d 章' % i, 'src': src, 'out': out, 'group': '正文'})
    for item in CFG['back']:
        src = ROOT / item['src']
        entries.append({'label': title_from_md(src), 'short': item.get('label', title_from_md(src)),
                        'src': src, 'out': item['out'], 'group': '附录'})
    src = ROOT / CFG['references']['src']
    entries.append({'label': title_from_md(src), 'short': '参考书目', 'src': src,
                    'out': CFG['references']['out'], 'group': '参考书目'})
    return entries

def build_index(entries):
    groups = []
    for g in ['前言', '正文', '附录', '参考书目']:
        items = [e for e in entries if e['group'] == g]
        if not items:
            continue
        lis = ''.join('<li><a href="%s">%s</a></li>' % (html.escape(e['out']), html.escape(e['label']))
                      for e in items)
        groups.append('<section class="toc-group"><h2>%s</h2><ol class="toc-list">%s</ol></section>'
                      % (g, lis))
    body = """
<section class="hero">
  <img class="cover" src="cover/cover.png" alt="%s 封面">
  <div class="info">
    <p class="series">%s</p>
    <h1>%s</h1>
    <p class="subtitle">%s</p>
    <p class="byline">%s　·　%s</p>
    <p class="intro">%s</p>
    <p><a class="btn" href="%s">开始阅读</a><a class="btn ghost" href="%s">查看配套代码</a></p>
  </div>
</section>
%s
""" % (html.escape(CFG['title']), html.escape(CFG['series']), html.escape(CFG['title']),
       html.escape(CFG['subtitle']), html.escape(CFG['author']), html.escape(CFG['affiliation']),
       html.escape(CFG['intro']), html.escape(entries[0]['out']), html.escape(CFG['repo']),
       '\n'.join(groups))
    (ROOT / 'index.html').write_text(shell('index.html', CFG['title'] + '：' + CFG['subtitle'],
                                           body, None, None), encoding='utf-8')

def main():
    entries = build_entries()
    build_index(entries)
    for i, e in enumerate(entries):
        prefix = '' if posixpath.dirname(e['out']) == '.' else '../'
        body = '<article class="article">%s</article>' % pandoc_body(e['src'], prefix)
        prev = entries[i - 1] if i > 0 else None
        nxt = entries[i + 1] if i + 1 < len(entries) else None
        (ROOT / e['out']).write_text(shell(e['out'], e['label'], body, prev, nxt), encoding='utf-8')
    (ROOT / '.nojekyll').write_text('', encoding='utf-8')
    print('Generated %d pages + index' % len(entries))

if __name__ == '__main__':
    main()
