#!/usr/bin/env python3
"""
r36_video.py <resolution>

Applies video/display configuration changes from video/<resolution>.ini
Uses *exactly* the same operations and logic as r36_controls.py for full code reuse.
Supported operations (per section):
- replace_line     : replace entire line matching 'match'
- replace_value    : replace only the value after '='
- add_before       : insert 'replace' line before matching line (skips if duplicate exists)
- add_after        : insert 'replace' line after matching line (skips if duplicate exists)
- delete_line      : delete line matching 'match'
- replace_file     : copy source_file to target_file (if target exists)

IMPORTANT FIX (for exactly 3 spaces in Kodi XML):
- replace_val now does .replace('\\x20', ' ') ONLY
- NO .strip() at all
- This lets you write \x20\x20\x20 in the INI file (exactly like you did with \t\t in controls)
- The first space after = in the INI is ignored by configparser, but every \x20 after that becomes a literal space
- Perfect sync with DTB selector + LED GPIO + controls + video.
"""

import sys
import re
import shutil
from pathlib import Path
from datetime import datetime
import configparser

LOG_FILE = Path("/boot/darkosre_device.log")
VIDEO_DIR = Path("/usr/local/bin/r36_config/video")

def log(msg: str):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"{ts} [r36_video.py] {msg}\n"
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

def main(resolution: str):
    ini_path = VIDEO_DIR / f"{resolution}.ini"
    if not ini_path.is_file():
        log(f"ERROR: Video profile not found: {ini_path}")
        # Fallback to default 640x480 if it exists
        fallback = VIDEO_DIR / "640x480.ini"
        if fallback.is_file():
            log(f"Falling back to 640x480.ini")
            ini_path = fallback
        else:
            sys.exit(1)

    log(f"Applying video profile: {resolution}")

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
        replace_val = data.get("replace", "").replace('\\x20', ' ')   # <<< EXACTLY what you asked: only the separator space after = is ignored, every \x20 is turned into a literal space

        if not match_pat:
            log(f"Skipping [{section}] — no match pattern")
            continue

        for fp in file_paths:
            apply_ini_change(fp, operation, match_pat, replace_val)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: r36_video.py <resolution>")
        sys.exit(1)

    main(sys.argv[1])

