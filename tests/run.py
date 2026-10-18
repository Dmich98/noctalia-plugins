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
translations = json.loads((plugin / "translations/uk-UA.json").read_text())
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
sources.append("local runtime = (function()\n" + (root / "tests/runtime.luau").read_text() + "\nend)()(sources, translations)")


def luau_value(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        # Fixed-width decimal escapes preserve control characters and literal JSON escapes.
        return '"' + "".join(
            "\\\\" if char == "\\" else '\\"' if char == '"'
            else f"\\{ord(char):03}" if ord(char) < 32 else char for char in value
        ) + '"'
    if isinstance(value, (int, float)):
        return repr(value)
    # Match host object keys passed through lua_setfield's NUL-terminated name.
    entries = enumerate(value, 1) if isinstance(value, list) else (
        (key.split("\0", 1)[0], item) for key, item in value.items()
    )
    return "{" + ",".join(f"[{luau_value(key)}]={luau_value(item)}" for key, item in entries) + "}"


def tagged_json(raw):
    # Independent reference transform: match whole strings before structural brackets.
    def replace(match):
        token = match.group()
        if token == "[":
            return "[true" if raw[match.end():].lstrip().startswith("]") else "[true,"
        return ",true]" if token == "]" else token

    return re.sub(r'"(?:\\.|[^"\\])*"|\[|\]', replace, raw)


fixture_dir = root / "tests/fixtures/neptun-ws"
fixtures = {
    name: (fixture_dir / f"{name}.jsonl").read_text().splitlines()
    for name in ("session-1", "session-2")
}
fixtures["cases"] = json.loads((fixture_dir / "synthetic-cases.json").read_text())
fixtures["cases"] += json.loads((fixture_dir / "validation-cases.json").read_text())
fixtures["projection"] = json.loads((fixture_dir / "projection-cases.json").read_text())
fixtures["service"] = json.loads((fixture_dir / "service-cases.json").read_text())
fixtures["threats"] = json.loads((fixture_dir / "threat-notifications.json").read_text())
json_values = {}
for raw in fixtures["session-1"] + fixtures["session-2"] + [case["raw"] for case in fixtures["cases"] + fixtures["projection"] + fixtures["service"] + fixtures["threats"]]:
    tagged = tagged_json(raw)
    try:
        json_values[tagged] = json.loads(tagged)
    except json.JSONDecodeError:
        pass
sources.append("local wsFixtures = " + luau_value(fixtures))
sources.append("local wsJsonValues = " + luau_value(json_values))
sources.append((root / "tests/checks.luau").read_text())
sources.append("do\n" + (root / "tests/transport.luau").read_text() + "\nend")
sources.append("do\n" + (root / "tests/ws-events.luau").read_text() + "\nend")

sources.append("do\n" + (root / "tests/ws-status.luau").read_text() + "\nend")

sources.append("do\n" + (root / "tests/ws-freshness.luau").read_text() + "\nend")
sources.append("do\n" + (root / "tests/geolocation.luau").read_text() + "\nend")
sources.append("do\n" + (root / "tests/threat-notifications.luau").read_text() + "\nend")
sources.append("do\n" + (root / "tests/threat-panel.luau").read_text() + "\nend")


sources.append("do\n" + (root / "tests/panel-placement.luau").read_text() + "\nend")

with tempfile.TemporaryDirectory(prefix="air-alert-tests-") as directory:
    script = Path(directory) / "checks.luau"
    script.write_text("\n".join(sources))
    executable = sys.argv[1] if len(sys.argv) > 1 else "luau"
    try:
        result = subprocess.run([executable, str(script)], check=False)
    except FileNotFoundError:
        sys.exit("Luau CLI not found. Run: python3 tests/run.py /path/to/luau")
    sys.exit(result.returncode)
