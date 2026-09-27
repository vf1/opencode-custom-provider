# opencode-custom-provider

Generate an [opencode](https://opencode.ai) provider config JSON from any
OpenAI-compatible `/models` API endpoint, enriched with `reasoning` and
`reasoningEffort` variants from [models.dev](https://models.dev).

## Quick start

```sh
./commandcode.sh
```

Produces `results/commandcode.json` — no need to remember the URL. Requires
Python 3 (stdlib only).

## Universal mode

```sh
python models.py <url> [-o output.json]
```

Without `-o` the JSON is printed to stdout.

Example:

```sh
python models.py https://api.example.com/v1/models -o results/provider.json
```

The output is grouped by `owned_by` and looks like:

```json
{
  "provider": {
    "some-vendor": {
      "models": {
        "some-model": {
          "id": "some-model",
          "reasoning": true,
          "options": { "contextLength": 200000 },
          "variants": {
            "low": { "options": { "reasoningEffort": "low" } }
          }
        }
      }
    }
  }
}
```

Copy the result into your opencode config (e.g. `opencode.json`) under `provider`.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/vf1/opencode-custom-provider/main/install.sh | sh
```

Adds/updates `models` in `~/.config/opencode/opencode.json`. Deps: `curl` +
POSIX `sh`/`awk`. The rest of the provider block (`npm`, `options.baseURL`,
`apiKey`) is yours to configure — a hint is printed if the block is missing.
If your config key differs from `command-code`, pass it:

```sh
curl -fsSL https://raw.githubusercontent.com/vf1/opencode-custom-provider/main/install.sh | sh -s -- commandcode
```

`--config PATH` targets another config, `OCC_URL` overrides the download URL.
A backup is saved to `<config>.bak` before the first change.

## Download

Raw `commandcode.json` for manual use:

```text
https://github.com/vf1/opencode-custom-provider/releases/download/files/commandcode.json
```

## Notes

- If models.dev is unreachable, generation proceeds without enrichment
  (no `reasoning` / `variants` fields).
- `variants` are added only for models with effort levels in models.dev that
  support OpenAI-style endpoints (`/chat/completions` or `/responses`).
