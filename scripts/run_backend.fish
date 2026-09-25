#!/usr/bin/env fish
set SCRIPT_DIR (dirname (status filename))
set ROOT (realpath "$SCRIPT_DIR/..")
cd "$ROOT/backend"; or exit 1

if not test -d .venv
    echo "Run ../scripts/setup_backend.fish first."
    exit 1
end

source .venv/bin/activate.fish
set -gx VIRANARI_DB_PATH "$ROOT/backend/data/viranari_v12.db"
if not set -q VIRANARI_JWT_SECRET
    set -gx VIRANARI_JWT_SECRET "local-hackathon-only-change-before-deploy-2026"
end
python run.py
