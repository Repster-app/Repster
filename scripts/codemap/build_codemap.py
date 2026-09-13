#!/usr/bin/env python3
"""Build an interactive map of the Repster codebase.

Reads the Swift source, works out which files reference types declared in which
other files, adds git churn, test reach and uncommitted state, and writes one
self-contained HTML page from codemap_template.html.

    python3 scripts/codemap/build_codemap.py
    python3 scripts/codemap/build_codemap.py --out /path/to/codemap.html

Approximate by design: it matches type names, it does not compile. Reliable at
the area level, indicative at the file level. Only top-level, non-private type
declarations are treated as referenceable, so nested helper types (`Row`,
`Mode`, ...) and file-private views never create false edges.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SOURCE_DIRS = ["Repster", "WorkoutLiveActivity"]
TEST_DIRS = ["RepsterTests"]
CHURN_DAYS = 90

TOP_DECL_RE = re.compile(
    r"^(?:@[\w.]+(?:\([^)]*\))?\s+)*"
    r"((?:(?:public|internal|private|fileprivate|final|open|indirect|nonisolated)\s+)*)"
    r"(class|struct|enum|protocol|actor|typealias)\s+([A-Z][A-Za-z0-9_]*)"
)
ANY_DECL_RE = re.compile(r"\b(?:class|struct|enum|protocol|actor|typealias)\s+([A-Z][A-Za-z0-9_]*)")
EXT_RE = re.compile(r"^(?:@[\w.]+(?:\([^)]*\))?\s+)*(?:(?:public|private|fileprivate)\s+)?extension\s+([A-Z][A-Za-z0-9_]*)")
TOP_FUNC_RE = re.compile(r"^(?:@[\w.]+(?:\([^)]*\))?\s+)*(?:(?:public|internal|nonisolated)\s+)?func\s+([a-z_][A-Za-z0-9_]*)")
IDENT_RE = re.compile(r"\b[A-Z][A-Za-z0-9_]*\b")
CALL_RE = re.compile(r"\b([a-z_][A-Za-z0-9_]*)\s*\(")


def strip_comments_and_strings(src: str) -> str:
    """Blank out comments and string literals so names in them don't count."""
    out = []
    i, n = 0, len(src)
    while i < n:
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j == -1 else j
        elif src.startswith("/*", i):
            depth, i = 1, i + 2
            while i < n and depth:
                if src.startswith("/*", i):
                    depth, i = depth + 1, i + 2
                elif src.startswith("*/", i):
                    depth, i = depth - 1, i + 2
                else:
                    if src[i] == "\n":
                        out.append("\n")
                    i += 1
        elif src.startswith('"""', i):
            j = src.find('"""', i + 3)
            end = n if j == -1 else j + 3
            out.append('""' + "\n" * src.count("\n", i, end))
            i = end
        elif src[i] == '"':
            i += 1
            while i < n and src[i] not in '"\n':
                i += 2 if src[i] == "\\" else 1
            i += 1
            out.append('""')
        else:
            out.append(src[i])
            i += 1
    return "".join(out)


def area_of(rel: str) -> tuple[str, str]:
    """Return (area id, layer) for a repo-relative path."""
    parts = rel.split("/")
    if parts[0] == "WorkoutLiveActivity":
        return "Widget/LiveActivity", "Widget"
    layer = parts[1]
    if layer == "App":
        return "App", "App"
    if layer in ("Features", "Core", "Data") and len(parts) > 3:
        return f"{layer}/{parts[2]}", layer
    return layer, layer


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, check=True).stdout


def git_history() -> tuple[dict, Counter, Counter]:
    """Last change date, all-time commit count and recent commit count per path."""
    last_changed, all_time, recent = {}, Counter(), Counter()
    cutoff = (date.today() - timedelta(days=CHURN_DAYS)).isoformat()
    current = None
    for line in git("log", "--format=@@%cs", "--name-only", "--no-renames").splitlines():
        if line.startswith("@@"):
            current = line[2:]
        elif line.strip():
            last_changed.setdefault(line, current)
            all_time[line] += 1
            if current >= cutoff:
                recent[line] += 1
    return last_changed, all_time, recent


def uncommitted_paths() -> set[str]:
    paths = set()
    for line in git("status", "--porcelain", "--untracked-files=all").splitlines():
        path = line[3:].split(" -> ")[-1].strip('"')
        paths.add(path)
    return paths


def swift_files(dirs: list[str]) -> list[Path]:
    return sorted(p for d in dirs for p in (ROOT / d).rglob("*.swift"))


def build() -> dict:
    sources = swift_files(SOURCE_DIRS)
    tests = swift_files(TEST_DIRS)

    files, stripped = [], []
    for path in sources:
        rel = path.relative_to(ROOT).as_posix()
        raw = path.read_text(encoding="utf-8", errors="replace")
        body = strip_comments_and_strings(raw)
        area, layer = area_of(rel)
        top_types, private_types, extends, funcs = [], [], [], []
        for line in body.splitlines():
            if m := TOP_DECL_RE.match(line):
                (private_types if "private" in m.group(1) else top_types).append(m.group(3))
            elif m := EXT_RE.match(line):
                extends.append(m.group(1))
            elif m := TOP_FUNC_RE.match(line):
                funcs.append(m.group(1))
        files.append({
            "path": rel,
            "name": path.name,
            "area": area,
            "layer": layer,
            "lines": raw.count("\n") + (0 if raw.endswith("\n") else 1),
            "types": top_types,
            "funcs": sorted(set(funcs)),
            "nestedTypes": sorted(set(ANY_DECL_RE.findall(body)) - set(top_types) - set(private_types)),
            "extends": sorted(set(extends)),
        })
        stripped.append(body)

    # Unique top-level name -> defining file index. Global functions (`dbg`, ...) count too,
    # matched only where they are called.
    def unique_owner(key: str) -> dict[str, int]:
        owners = defaultdict(set)
        for idx, f in enumerate(files):
            for name in f[key]:
                owners[name].add(idx)
        return {name: next(iter(ix)) for name, ix in owners.items() if len(ix) == 1}

    type_owner = unique_owner("types")
    func_owner = unique_owner("funcs")

    def references(body: str, own: int | None) -> dict[int, Counter]:
        hits = defaultdict(Counter)
        for pattern, owner in ((IDENT_RE, type_owner), (CALL_RE, func_owner)):
            for match in pattern.finditer(body):
                name = match.group(1) if pattern.groups else match.group(0)
                target = owner.get(name)
                if target is not None and target != own:
                    hits[target][name] += 1
        return hits

    edges = []
    for idx, body in enumerate(stripped):
        for target, names in references(body, idx).items():
            edges.append({
                "from": idx,
                "to": target,
                "weight": sum(names.values()),
                "via": [n for n, _ in names.most_common(4)],
            })

    test_reach = Counter()
    for path in tests:
        body = strip_comments_and_strings(path.read_text(encoding="utf-8", errors="replace"))
        for target in references(body, None):
            test_reach[target] += 1

    last_changed, all_time, recent = git_history()
    dirty = uncommitted_paths()
    for idx, f in enumerate(files):
        f["tests"] = test_reach[idx]
        f["churn"] = recent[f["path"]]
        f["commits"] = all_time[f["path"]]
        f["lastChanged"] = last_changed.get(f["path"])
        f["dirty"] = f["path"] in dirty or any(f["path"].startswith(d.rstrip("/") + "/") for d in dirty if d.endswith("/"))

    area_edges = defaultdict(lambda: {"weight": 0, "pairs": 0, "via": Counter()})
    for e in edges:
        a, b = files[e["from"]]["area"], files[e["to"]]["area"]
        agg = area_edges[(a, b)]
        agg["weight"] += e["weight"]
        agg["pairs"] += 1
        for name in e["via"]:
            agg["via"][name] += 1

    areas = defaultdict(lambda: {"files": 0, "lines": 0})
    for f in files:
        areas[(f["area"], f["layer"])]["files"] += 1
        areas[(f["area"], f["layer"])]["lines"] += f["lines"]

    return {
        "generated": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "commit": git("rev-parse", "--short", "HEAD").strip(),
        "branch": git("rev-parse", "--abbrev-ref", "HEAD").strip(),
        "churnDays": CHURN_DAYS,
        "testFiles": len(tests),
        "areas": [{"id": a, "layer": layer, **v} for (a, layer), v in areas.items()],
        "files": files,
        "edges": edges,
        "areaEdges": [
            {"from": a, "to": b, "weight": v["weight"], "pairs": v["pairs"], "via": [n for n, _ in v["via"].most_common(5)]}
            for (a, b), v in area_edges.items()
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, default=HERE / "codemap.html")
    parser.add_argument("--json", type=Path, help="also write the raw data as JSON")
    args = parser.parse_args()

    data = build()
    payload = json.dumps(data, separators=(",", ":")).replace("</", "<\\/")
    template = (HERE / "codemap_template.html").read_text(encoding="utf-8")
    args.out.write_text(template.replace("/*__CODEMAP_DATA__*/null", payload), encoding="utf-8")
    if args.json:
        args.json.write_text(json.dumps(data, indent=1), encoding="utf-8")

    lines = sum(f["lines"] for f in data["files"])
    print(f"{len(data['files'])} files, {lines:,} lines, {len(data['edges'])} file edges -> {args.out}")


if __name__ == "__main__":
    main()
