# Archivist

Archivist is a native macOS menu bar app that watches your Downloads folder,
uses AI to understand what each new file actually is, and makes your files
searchable and organizable without you having to sort them by hand.

It runs quietly in the background (no Dock icon, just a menu bar icon). When a
new file lands in Downloads, Archivist reads it, asks an AI model to figure
out what it is (a resume, an invoice, a screenshot, a paper, etc.), tags it,
proposes a clean filename, and files it away — so you can later search for
"that PDF about the lease" instead of digging through a folder of
`Untitled-4.pdf` and `IMG_2938.png`.

## Requirements

- macOS 13 (Ventura) or later
- Xcode command line tools with a Swift 5.9+ toolchain (install via
  `xcode-select --install`, or Xcode itself)
- [Ollama](https://ollama.com) if you want to run everything locally for free
  (recommended — see [Setting up an AI provider](#setting-up-an-ai-provider)),
  or an API key for a cloud provider

## Getting the code

```bash
git clone <this-repo-url>
cd ArunimaYadav_Capstone/macapp
```

All the Swift package files live under `macapp/`, so run the `swift`
commands below from that directory.

## Building

```bash
swift build
```

This fetches dependencies (none beyond system libraries — Archivist links
against `sqlite3` and `CoreServices`) and compiles the `Archivist` target.

## Running

```bash
swift run
```

This launches Archivist as a menu bar app. Look for the archive-box icon in
your menu bar and click it to open the popover UI (search, review queue, and
settings). The app has no Dock icon by design — it's a background utility.

On first launch, Archivist starts watching `~/Downloads` for new files.

## Organizing files with natural language

Beyond auto-filing new downloads, you can type a plain-English command like
"put my bank files in one folder" into the Organize tab. Archivist finds the
matching indexed files and shows you a preview — the destination folder name
and the exact files it plans to move — before touching anything. Nothing
moves until you click **Confirm and move**.

## Setting up an AI provider

Archivist needs an AI provider to understand files. Open the menu bar icon →
**Settings** → **AI Provider** to configure one.

### Option 1: Ollama (free, local, recommended)

Ollama runs models on your own Mac, so no API key is needed and no file
content ever leaves your machine. This is the default provider.

1. Install Ollama from [ollama.com](https://ollama.com).
2. Start it and pull the models Archivist uses:

   ```bash
   ollama serve
   ollama pull llama3.1:8b
   ollama pull nomic-embed-text
   ```

3. Leave the provider in Settings set to **Ollama (local)** (this is the
   default when no cloud provider is configured). Archivist talks to Ollama
   on `http://localhost:11434`.

Local inference is slower and more variable than a cloud API (requests can
take anywhere from tens of seconds to a couple of minutes), so expect some
lag on modest hardware — this is a deliberate tradeoff for keeping everything
free and on-device.

### Option 2: Cloud providers (optional, faster)

If you'd rather trade a paid API key for speed, Archivist also supports:

- OpenAI
- Anthropic
- Groq (a free key is available at
  [console.groq.com/keys](https://console.groq.com/keys))
- Gemini

In Settings, pick a provider from the **Preferred provider** dropdown, then
enter its API key under **API Keys** and click **Save**. Keys are stored
securely in the macOS Keychain, never in plain text on disk. If a cloud
provider isn't configured, or a call to it fails, Archivist automatically
falls back to local Ollama.

## Other settings

- **Watching** — optionally also watch the Desktop folder, and tune the
  confidence threshold Archivist uses before auto-filing a file versus
  sending it to the review queue.
- **Naming** — set your name so files identified as your own work get named
  consistently (e.g. `YourName_Title_2026-09-19.pdf`).

## Known Limitations

- No backfill: Archivist only processes files downloaded after the app
  starts running. Files already sitting in Downloads before launch are left
  alone.
