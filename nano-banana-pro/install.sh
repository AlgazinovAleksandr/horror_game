#!/usr/bin/env bash
# Install dependencies for the nano-banana-pro Claude Code skill.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 not found. install Python 3.10+ first." >&2
  exit 1
fi

PIP_CMD=(python3 -m pip install --upgrade -r "$SKILL_DIR/requirements.txt")
if ! "${PIP_CMD[@]}"; then
  echo "pip install failed; retrying with --user..." >&2
  "${PIP_CMD[@]}" --user
fi

echo
echo "deps installed."
echo
if [ -z "${GEMINI_API_KEY:-}" ] && [ -z "${GOOGLE_API_KEY:-}" ]; then
  cat <<'EOF'
next: get an API key at https://aistudio.google.com/apikey and add to your shell rc:

  export GEMINI_API_KEY=your_key_here

then reload your shell (or `source ~/.zshrc`) and try:

  python3 ~/.claude/skills/nano-banana-pro/generate_image.py "a cute robot reading a book" -o test.png
EOF
else
  echo "GEMINI_API_KEY detected. you're ready to go."
fi
