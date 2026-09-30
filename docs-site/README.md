# NetCrux user documentation

The source of **https://docs.netcrux.app/** — the NetCrux user guide, written in
Markdown and built with [MkDocs](https://www.mkdocs.org/) and
[Material for MkDocs](https://squidfunk.github.io/mkdocs-material/). This file
is not part of the built site.

## Preview and build

Use the same pinned versions CI uses:

```bash
python3 -m venv .venv
.venv/bin/pip install mkdocs==1.6.0 mkdocs-material==9.5.27 \
  pymdown-extensions==10.9 Pygments==2.19.2
```

From `docs-site/`:

```bash
../.venv/bin/mkdocs serve            # live preview at http://127.0.0.1:8000
../.venv/bin/mkdocs build --strict   # what CI runs; any warning fails
```

(Adjust the venv path to wherever you created it.) The build writes `site/`,
which is git-ignored.

`.github/workflows/docs.yml` builds the site on every pull request that touches
`docs-site/`, and on merge to `main` deploys `site/` to Cloudflare Workers
Static Assets (`wrangler.jsonc`). The deploy step skips itself when the
Cloudflare secrets are not configured.

## Conventions

- **One page per URL, same slug.** User docs used to live at
  `netcrux.app/docs/<slug>`. Each of those pages is `docs/<slug>.md` here and
  builds to `<slug>.html` (`use_directory_urls: false`), which the Workers
  host serves at `/<slug>`. Do not rename a page or remove a heading `{#id}`
  without a redirect plan — the app and old links point at them.
- **Tier badges.** Mark a paid feature after its heading or name with exactly
  `<span class="tier tier-pro">Pro</span>`,
  `<span class="tier tier-enterprise">Enterprise</span>` or
  `<span class="tier tier-edu">EDU</span>`. They are styled by
  `docs/assets/brand.css`.
- **Keys** use `pymdownx.keys`, macOS first: `++cmd+o++ / ++ctrl+o++`.
- **Labels are literal.** Menu items, buttons and settings are written exactly
  as the English UI shows them.
- **Known issues** that make a documented feature misbehave get a
  `!!! warning "Known issue"` admonition stating the current behaviour.
- Links between pages are relative `.md` links (strict mode checks them);
  marketing pages are absolute `https://netcrux.app/<page>`; suite pages are
  `https://edacrux.app/<page>`.

## Behaviour changes update these pages

A pull request that changes something a user can see — a menu label, a
shortcut, a setting, a file format, what a feature does or which tier it needs
— updates the affected page here in the same pull request.
