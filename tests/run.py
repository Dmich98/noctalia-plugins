"""Run production Luau modules with a small mocked Noctalia environment."""

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
plugin = root / "air-alert"
sources = ["local sources = {}"]
translations = json.loads((plugin / "translations/uk.json").read_text())
sources.append("local translations = {")
for key, value in translations.items():
    sources.append(f"[{json.dumps(key, ensure_ascii=False)}] = {json.dumps(value, ensure_ascii=False)},")
sources.append("}")
for path in sorted(plugin.rglob("*.luau")):
    key = json.dumps("./" + path.relative_to(plugin).as_posix())

    def resolve_require(match):
        target = (path.parent / match.group(1)).resolve().relative_to(plugin)
        return f'require("./{target.as_posix()}")'

    # Noctalia resolves each module's literal imports relative to that module.
    code = re.sub(r'require\("([^"]+)"\)', resolve_require, path.read_text())
    code = json.dumps(code, ensure_ascii=False)
    sources.append(f"sources[{key}] = {code}")
sources.append((root / "tests" / "checks.luau").read_text())

with tempfile.TemporaryDirectory(prefix="air-alert-tests-") as directory:
    script = Path(directory) / "checks.luau"
    script.write_text("\n".join(sources))
    executable = sys.argv[1] if len(sys.argv) > 1 else "luau"
    try:
        result = subprocess.run([executable, str(script)], check=False)
    except FileNotFoundError:
        sys.exit("Luau CLI not found. Run: python3 tests/run.py /path/to/luau")
    sys.exit(result.returncode)
