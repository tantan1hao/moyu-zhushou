# Word Novel Proxy

Word Novel Proxy is a macOS prototype that intercepts `Space`, `Return`,
and `Delete` while Microsoft Word or WPS is the frontmost application. Instead of
typing normally, it advances through a prepared `.txt` source and injects the
novel into the active Word document.

## Current behavior

- Manual enable or disable from the menu bar.
- Only active when the frontmost bundle id is `com.microsoft.Word` or `com.kingsoft.wpsoffice.mac`.
- Source text is loaded from a local `.txt` file.
- Empty lines split paragraphs.
- Whitespace inside a paragraph is normalized before playback.
- `Space` emits the next character from the current paragraph.
- `Return` skips to the next paragraph and inserts a newline.
- `Delete` removes the most recently injected output and rewinds the engine.

## Requirements

- macOS with Microsoft Word or WPS installed.
- Python 3.13 or newer.
- Accessibility and Input Monitoring permissions.

Install dependencies:

```bash
python3 -m pip install -r /Users/mac/word/requirements.txt
```

Run the app:

```bash
python3 /Users/mac/word/main.py
```

## Notes

- The prototype does not verify that the current Word document is truly blank.
  That is a manual usage rule in v1.
- Windows support is intentionally left for a later platform adapter.
