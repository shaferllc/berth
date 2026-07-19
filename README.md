# Berth

*Berth — a place to tie up and return to.*

Berth is a native macOS bookmark manager in the spirit of MarkWell: save a
link in a second, hang a few tags on it, and actually find it again next
month. It saves **links with metadata** — title, description, favicon — not
article bodies. If you want full article capture for offline reading, that's
the job of its sibling app [stow](../stow); Berth stays deliberately lighter.
Everything lives in a single JSON file on your Mac. No account, no cloud.

## Features

- Three-pane window: sidebar (All / Favorites / Untagged / Tags with counts),
  bookmark list with favicon, domain, tag chips and added date (list or
  compact rows), and a detail pane with editable title, note, and tags.
- Add from anywhere: ⌘N sheet, ⌘⇧V grabs the URL on the clipboard, or drag a
  link from your browser onto the window or the Dock icon.
- On save, Berth does one lightweight fetch (5 s timeout) to fill in the page
  title, meta description, and favicon (cached on disk). Offline? The link is
  saved anyway, marked pending, with a retry button.
- Freeform tags with autocomplete from your existing tags. Click any chip to
  filter; ⌘-click tags in the sidebar to combine filters.
- Instant search-as-you-type across title, URL, description, note, and tags
  (⌘F). Sort by date added, title, or domain.
- Open in your default browser (⌘↩ or double-click), copy URL, favorite star,
  delete with ⌘Z undo (a soft-delete stack — no scary dialogs).
- Duplicate detection: adding a URL you already saved offers to show the
  existing bookmark instead.
- Import/export JSON, and export Netscape bookmarks HTML that Safari, Chrome,
  and Firefox can import.
- Storage: one debounced, atomically-written JSON file in
  `~/Library/Application Support/Berth/`.

## Build

```
./make-app.sh
```

Builds a release binary, generates the icon, assembles `Berth.app`, installs
it to /Applications, and launches it.

## Not yet

- iPhone/iPad sync — v1 is Mac-only; sync is the obvious next step.
- Netscape HTML *import* (export works; import currently takes Berth JSON).
- A browser extension for one-click saving.
