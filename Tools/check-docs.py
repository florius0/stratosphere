"""Check local Markdown links, product IDs, and DOT syntax without generated source files."""

from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]


def anchors(content):
    counts = {}
    result = set()
    for title in re.findall(r"^#{1,6}\s+(.+?)\s*#*\s*$", content, re.M):
        name = "".join(character for character in title.lower() if character.isalnum() or character in " -_")
        name = name.replace(" ", "-")
        count = counts.get(name, 0)
        counts[name] = count + 1
        result.add(name + (f"-{count}" if count else ""))
    return result


def main():
    files = [ROOT / "AGENTS.md", *sorted((ROOT / "docs").rglob("*.md"))]
    if (ROOT / "README.md").exists():
        files.append(ROOT / "README.md")
    definitions = set()
    for name in ["concepts.md", "feature-map.md", "functional-requirements.md", "non-functional-requirements.md", "decision-map.md"]:
        content = (ROOT / "docs" / name).read_text()
        definitions.update(re.findall(r"(?:^## |\*\*|\| )(C-\d+|FR-\d+|NFR-\d+|D-\d+|Q-\d+|F-\d+)(?=:?\*\*| —| \|)", content, re.M))
    failures = []
    for file in files:
        content = file.read_text()
        for reference in re.findall(r"\b(?:C|FR|NFR|D|Q|F)-\d+\b", content):
            if reference not in definitions:
                failures.append(f"{file.relative_to(ROOT)}: unknown product ID {reference}")
        for target in re.findall(r"\[[^\]]*\]\(([^\s)]+)\)", content):
            if "://" in target or target.startswith(("mailto:", "app:")):
                continue
            path, separator, fragment = target.partition("#")
            destination = file.parent / unquote(path) if path else file
            if not destination.exists():
                failures.append(f"{file.relative_to(ROOT)}: missing link {target}")
            elif separator and fragment and destination.suffix == ".md" and unquote(fragment) not in anchors(destination.read_text()):
                failures.append(f"{file.relative_to(ROOT)}: missing anchor {target}")
    dot = shutil.which("dot")
    if dot is None:
        failures.append("Graphviz is required to validate the DOT summaries")
    else:
        with tempfile.TemporaryDirectory(prefix="stratosphere-diagrams-") as output:
            for file in sorted((ROOT / "docs").rglob("*.dot")):
                result = subprocess.run([dot, "-Tsvg", str(file), "-o", str(Path(output) / (file.stem + ".svg"))], capture_output=True, text=True)
                if result.returncode:
                    failures.append(f"{file.relative_to(ROOT)}: {result.stderr.strip()}")
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    print(f"Documentation links and product references checked in {len(files)} files; DOT summaries parsed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
