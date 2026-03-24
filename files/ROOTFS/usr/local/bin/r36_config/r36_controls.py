#!/usr/bin/env python3
"""
r36_controls.py <scheme>

Applies control scheme changes from controls/<scheme>.ini

Supported operations (per section):
- replace_line     : replace entire line matching 'match'
- replace_value    : replace only the value after '='
- add_before       : insert 'replace' line before matching line (skips if duplicate exists)
- add_after        : insert 'replace' line after matching line (skips if duplicate exists)
- delete_line      : delete line matching 'match'
- replace_file     : copy source_file to target_file (if target exists)
"""

import sys
import re
import shutil
from pathlib import Path
from datetime import datetime
import configparser

LOG_FILE = Path("/boot/darkosre_device.log")
CONTROLS_DIR = Path("/usr/local/bin/r36_config/controls")

def log(msg: str):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"{ts} [r36_controls.py] {msg}\n"
    try:
        with LOG_FILE.open("a", encoding="utf-8") as f:
            f.write(line)
    except:
        pass

def apply_ini_change(file_path: Path, operation: str, match: str, replace: str = ""):
    """
    Applies line-based operations to INI/CFG-like files
    Includes duplicate prevention for add_before/add_after
    """
    if not file_path.is_file():
        log(f"SKIP (missing): {file_path}")
        return

    if not file_path.stat().st_mode & 0o200:
        log(f"SKIP (not writable): {file_path}")
        return

    log(f"Processing {file_path}  op={operation}  match='{match}'  replace='{replace}'")

    try:
        original = file_path.read_text(encoding="utf-8", errors="replace")
        content = original

        # Normalize pattern to full-line match
        pattern = match.strip()
        if not pattern.startswith('^'):
            pattern = '^' + pattern
        if not pattern.endswith('$'):
            pattern += '$'

        # Duplicate prevention for add_before / add_after
        if operation in ("add_before", "add_after"):
            if replace in content:
                log(f"  → SKIP {operation} (duplicate: '{replace}' already present)")
                return

        if operation == "replace_line":
            content = re.sub(pattern, replace, content, flags=re.MULTILINE)

        elif operation == "replace_value":
            content = re.sub(rf"({pattern})\s*=\s*([^#\n]*)", rf"\1 = {replace}", content, flags=re.MULTILINE)

        elif operation == "add_before":
            content = re.sub(pattern, f"{replace}\n\\g<0>", content, flags=re.MULTILINE)

        elif operation == "add_after":
            content = re.sub(pattern, f"\\g<0>\n{replace}", content, flags=re.MULTILINE)

        elif operation == "delete_line":
            content = re.sub(pattern + r'\n?', "", content, flags=re.MULTILINE)

        else:
            log(f"Unknown operation '{operation}'")
            return

        if content != original:
            file_path.write_text(content, encoding="utf-8")
            log(f"  → CHANGED")
        else:
            log(f"  → no match / no change")

    except Exception as e:
        log(f"Error in {file_path}: {type(e).__name__} - {e}")

def apply_file_copy(source: str, target: str):
    """
    Copy source → target (only if target already exists)
    """
    src = Path(source.strip('" '))
    tgt = Path(target.strip('" '))

    if not src.is_file():
        log(f"SKIP copy - source missing: {src}")
        return

    if not tgt.is_file():
        log(f"SKIP copy - target does not exist: {tgt}")
        return

    if not tgt.stat().st_mode & 0o200:
        log(f"SKIP copy - target not writable: {tgt}")
        return

    try:
        shutil.copy2(src, tgt)
        log(f"COPY OK: {src} → {tgt}")
    except Exception as e:
        log(f"COPY FAILED {src} → {tgt}: {e}")

def main(scheme: str):
    ini_path = CONTROLS_DIR / f"{scheme}.ini"
    if not ini_path.is_file():
        log(f"ERROR: Scheme file not found: {ini_path}")
        sys.exit(1)

    log(f"Applying scheme: {scheme}")

    parser = configparser.ConfigParser(allow_no_value=True, delimiters=("=",))
    parser.optionxform = str  # case sensitive
    parser.read(ini_path)

    for section in parser.sections():
        data = parser[section]

        # File copy mode
        if "source_file" in data and "target_file" in data:
            apply_file_copy(data["source_file"], data["target_file"])
            continue

        # Line edit mode
        files_str = data.get("files", "").strip('" ')
        if files_str:
            file_paths = [Path(p.strip()) for p in files_str.split(",") if p.strip()]
        else:
            log(f"Skipping [{section}] — no files defined")
            continue

        operation = data.get("operation", "replace_line").strip()
        match_pat = data.get("match", "").strip('" ')
        replace_val = data.get("replace", "").strip()

        if not match_pat:
            log(f"Skipping [{section}] — no match pattern")
            continue

        for fp in file_paths:
            apply_ini_change(fp, operation, match_pat, replace_val)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: r36_controls.py <scheme_name>")
        sys.exit(1)

    main(sys.argv[1])