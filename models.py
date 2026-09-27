#!/usr/bin/env python3
"""Generate an opencode provider config JSON from any OpenAI-compatible
/models API endpoint, enriched with reasoning/effort metadata from models.dev.

Usage:
    python models.py <url> [-o output.json]
"""

import argparse
import json
import os
import sys
import urllib.request

MODELS_DEV_URL = "https://models.dev/api.json"
TIMEOUT = 15
UA = "models-config-gen/1.0"

OPENAI_STYLE_ENDPOINTS = ("/chat/completions", "/responses")


def fetch_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return json.loads(resp.read().decode())


def load_models_dev():
    try:
        return fetch_json(MODELS_DEV_URL)
    except Exception as e:
        print(f"warning: failed to fetch {MODELS_DEV_URL}: {e}; continuing without enrichment", file=sys.stderr)
        return {}


def index_models_dev(md):
    index = {}
    for provider in md.values():
        for model in (provider or {}).get("models", {}).values():
            if model.get("id"):
                index[model["id"]] = model
    return index


def lookup(index, model_id):
    if model_id in index:
        return index[model_id]
    _, _, tail = model_id.partition("/")
    return index.get(tail) if tail else None


def effort_values(meta):
    for opt in (meta or {}).get("reasoning_options") or []:
        if opt.get("type") == "effort" and opt.get("values"):
            return opt["values"]
    return []


def enrich(model, meta):
    entry = {"id": model["id"]}
    if meta and meta.get("reasoning") is True:
        entry["reasoning"] = True
    entry["options"] = {"contextLength": model.get("context_length")}
    endpoints = model.get("supported_endpoints") or []
    openai_style = any(e in endpoints for e in OPENAI_STYLE_ENDPOINTS)
    efforts = effort_values(meta)
    if efforts and openai_style:
        entry["variants"] = {lvl: {"options": {"reasoningEffort": lvl}} for lvl in efforts}
    return entry


def parse_args():
    parser = argparse.ArgumentParser(
        description="Generate an opencode provider config JSON from a models API endpoint."
    )
    parser.add_argument("url", help="models API endpoint (OpenAI-compatible /models)")
    parser.add_argument("-o", "--output", help="write JSON to this file instead of stdout")
    return parser.parse_args()


def main():
    args = parse_args()
    try:
        data = fetch_json(args.url)
    except Exception as e:
        print(f"error: failed to fetch {args.url}: {e}", file=sys.stderr)
        sys.exit(1)

    index = index_models_dev(load_models_dev())
    groups = {}
    for model in data.get("data") or []:
        if model.get("id") is None:
            continue
        meta = lookup(index, model["id"])
        groups.setdefault(model.get("owned_by") or "unknown", {})[model["id"]] = enrich(model, meta)

    output = json.dumps({"provider": {name: {"models": models} for name, models in groups.items()}}, indent=2)
    if args.output:
        parent = os.path.dirname(args.output)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(args.output, "w") as f:
            f.write(output + "\n")
    else:
        print(output)


if __name__ == "__main__":
    main()
