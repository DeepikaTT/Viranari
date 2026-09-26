#!/usr/bin/env fish
set SCRIPT_DIR (dirname (status filename))
set ROOT (realpath "$SCRIPT_DIR/..")
cd "$ROOT/backend"; or exit 1

if not test -d .venv
    python3 -m venv .venv; or exit 1
end
source .venv/bin/activate.fish
python -m pip install --upgrade pip; or exit 1
pip install -r requirements.txt; or exit 1
mkdir -p data

echo
echo "Backend dependencies installed."
echo "Next: ../scripts/run_backend.fish"
