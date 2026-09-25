#!/usr/bin/env fish
set SCRIPT_DIR (dirname (status filename))
set ROOT (realpath "$SCRIPT_DIR/..")
cd "$ROOT/backend"; or exit 1
if not test -d .venv
    echo "Run ../scripts/setup_backend.fish first."
    exit 1
end
source .venv/bin/activate.fish
pytest -q
