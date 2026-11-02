"""Measures what Matcha uses (task 11.1): processor and memory of each process working for it, its own and those of
WebKit (pages, extensions, network, graphics and media) or of macOS (video decoding, audio…), with their total.

    python3 -I scripts/perf.py                  one measure
    python3 -I scripts/perf.py --watch 5        one measure every 5 seconds, until ⌃C
    python3 -I scripts/perf.py --csv perf.csv   also adds the measures to a CSV file, created if needed
    python3 -I scripts/perf.py --pid 792        the Matcha with this PID, when several are open

The processes are those of Matcha's coalition, the group macOS makes of an app and of the services working for it
(Activity Monitor counts energy the same way), read with `lsappinfo` along with their names ("Matcha Web Content",
"Bitwarden Web Extension"). Memory: the footprint (`footprint`, Activity Monitor's "Memory" column; the resident size
counts shared memory too) and its peak since the process started. Processor: `top`, over one second (100 % = one core).
Depends only on Python and the tools of macOS.
"""

from __future__ import annotations

import argparse
import csv
import datetime
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field

APP_BUNDLE = "com.matchabrowser.matcha"

# Groups shown, in this order: key (written in the CSV files) and title.
GROUPS = [
    ("app", "App"),
    ("pages", "Pages"),
    ("extensions", "Extensions"),
    ("network", "Réseau"),
    ("gpu", "Graphisme et médias"),
    ("other", "Autres"),
]
# Group of WebKit's processes, by executable.
WEBKIT_KINDS = {
    "com.apple.WebKit.WebContent": "pages",
    "com.apple.WebKit.Networking": "network",
    "com.apple.WebKit.GPU": "gpu",
}
# What the services macOS starts for the app do, for those LaunchServices gives no name.
SERVICES = {
    "VTDecoderXPCService": "décodage vidéo",
    "MTLCompilerService": "compilation Metal",
    "com.apple.audio.SandboxHelper": "audio",
}
CSV_FIELDS = ["time", "pid", "kind", "name", "cpu_percent", "footprint_bytes", "peak_bytes"]

ENTRY = re.compile(r'^\s*\d+\) "(?P<name>.*)" ASN:')
FIELD = re.compile(r'^\s*(?P<key>bundleID|bundle path)="(?P<value>[^"]*)"')
PID = re.compile(r"^\s*pid = (?P<pid>\d+)\b")
COALITION = re.compile(r"^\s*coalition: \d+\s+\{(?P<pids>[\d\s]*)\}")
SAMPLE = re.compile(r"^\s*(?P<pid>\d+)\s+(?P<cpu>\d+(?:\.\d+)?)\s*$")


class PerfError(Exception):
    """A measure that can't be made; its message is shown as is."""


@dataclass
class Entry:
    """A process LaunchServices knows (`lsappinfo list`)."""

    name: str
    pid: int | None = None
    bundle: str = ""
    path: str = ""
    coalition: list[int] = field(default_factory=list)


@dataclass
class Process:
    pid: int
    name: str
    kind: str
    cpu: float | None = None
    footprint: int | None = None
    peak: int | None = None


def parse_listing(text):
    entries = []
    for line in text.splitlines():
        if match := ENTRY.match(line):
            entries.append(Entry(match["name"]))
        elif not entries:
            continue
        elif match := FIELD.match(line):
            if match["key"] == "bundleID":
                entries[-1].bundle = match["value"]
            else:
                entries[-1].path = match["value"]
        elif match := PID.match(line):
            entries[-1].pid = int(match["pid"])
        elif match := COALITION.match(line):
            entries[-1].coalition = [int(pid) for pid in match["pids"].split()]
    return entries


def instance(entries, pid=None):
    """The Matcha to measure: the only one open, or the one with this PID."""
    apps = [entry for entry in entries if entry.bundle == APP_BUNDLE and entry.pid]
    if pid is not None:
        apps = [app for app in apps if app.pid == pid]
        if not apps:
            raise PerfError(f"Aucun Matcha ouvert n'a le PID {pid}.")
    if not apps:
        raise PerfError("Matcha n'est pas ouvert.")
    if len(apps) > 1:
        listed = "\n".join(f"  --pid {app.pid}   {app.path}" for app in apps)
        raise PerfError(f"Plusieurs Matcha sont ouverts, choisir celui à mesurer :\n{listed}")
    return apps[0]


def parse_executables(text):
    """Executable of each process, from `ps -o pid=,comm=` (full paths, possibly with spaces)."""
    executables = {}
    for line in text.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2 and parts[0].isdigit():
            executables[int(parts[0])] = parts[1].strip().rsplit("/", 1)[-1]
    return executables


def parse_top(text):
    """Processor of each process in the last sample of `top -l 2` (the first one has no interval to measure over)."""
    lines = text.splitlines()
    headers = [index for index, line in enumerate(lines) if line.split()[:1] == ["PID"]]
    usage = {}
    for line in lines[headers[-1] + 1 :] if headers else []:
        if match := SAMPLE.match(line):
            usage[int(match["pid"])] = float(match["cpu"])
    return usage


def parse_footprint(text):
    """Footprint and peak of each process, in bytes, from `footprint --json`."""
    try:
        report = json.loads(text)
    except ValueError:
        return {}
    memory = {}
    for process in report.get("processes", []):
        if "pid" in process and "footprint" in process:
            peak = process.get("auxiliary", {}).get("phys_footprint_peak")
            memory[process["pid"]] = (process["footprint"], peak)
    return memory


def run_tool(arguments):
    """Output of a macOS tool. Its status is ignored: a process that ended in between makes it fail."""
    try:
        return subprocess.run(arguments, capture_output=True, text=True, check=False).stdout
    except FileNotFoundError:
        raise PerfError(f"Outil introuvable : {arguments[0]}.") from None


def memory_of(pids, run):
    with tempfile.TemporaryDirectory() as folder:
        report = pathlib.Path(folder) / "footprint.json"
        run(["footprint", "--noCategories", "--format", "bytes", "--json", str(report), *map(str, pids)])
        return parse_footprint(report.read_text()) if report.exists() else {}


def processor_of(pids, run):
    arguments = ["top", "-l", "2", "-s", "1", "-stats", "pid,cpu"]
    for pid in pids:
        arguments += ["-pid", str(pid)]
    return parse_top(run(arguments))


def kind_of(pid, executable, name, app):
    if pid == app.pid:
        return "app"
    kind = WEBKIT_KINDS.get(executable, "other")
    # WebKit names the process of an extension after the extension, those of the pages after the app.
    if kind == "pages" and name and app.name not in name:
        return "extensions"
    return kind


def display_name(executable, name):
    if name:
        return name
    service = SERVICES.get(executable)
    return f"{executable} ({service})" if service else executable


def measure(run=run_tool, pid=None):
    entries = parse_listing(run(["lsappinfo", "list"]))
    app = instance(entries, pid)
    members = sorted(set(app.coalition) | {app.pid})
    executables = parse_executables(run(["ps", "-o", "pid=,comm=", "-p", ",".join(map(str, members))]))
    # A process that ended in between is left out.
    members = [member for member in members if member in executables]
    names = {entry.pid: entry.name for entry in entries if entry.pid}
    memory = memory_of(members, run)
    processor = processor_of(members, run)
    processes = []
    for member in members:
        executable, name = executables[member], names.get(member)
        footprint, peak = memory.get(member, (None, None))
        kind = kind_of(member, executable, name, app)
        processes.append(Process(member, display_name(executable, name), kind, processor.get(member), footprint, peak))
    return processes


def format_memory(size):
    """Binary units, as Activity Monitor shows them."""
    if size is None:
        return "—"
    for unit, scale in (("Go", 1 << 30), ("Mo", 1 << 20), ("Ko", 1 << 10)):
        if size >= scale:
            value = size / scale
            return f"{value:.1f} {unit}".replace(".", ",") if value < 10 else f"{value:.0f} {unit}"
    return f"{size} o"


def format_processor(value):
    return "—" if value is None else f"{value:.1f} %".replace(".", ",")


def total(values):
    known = [value for value in values if value is not None]
    return sum(known) if known else None


def render(processes, now):
    """A line per group with its total, its processes below it from the largest, then the overall total."""
    rows = []
    for key, title in GROUPS:
        group = sorted((process for process in processes if process.kind == key), key=lambda p: -(p.footprint or 0))
        if not group:
            continue
        label = f"{title} ({len(group)})" if len(group) > 1 else title
        cpu, footprint = total(p.cpu for p in group), total(p.footprint for p in group)
        rows.append((label, "", format_processor(cpu), format_memory(footprint), ""))
        for p in group:
            figures = (format_processor(p.cpu), format_memory(p.footprint), format_memory(p.peak))
            rows.append((f"  {p.name}", str(p.pid), *figures))
    cpu, footprint = total(p.cpu for p in processes), total(p.footprint for p in processes)
    overall = (f"Total ({len(processes)} processus)", "", format_processor(cpu), format_memory(footprint), "")
    header = ("", "PID", "Processeur", "Mémoire", "Pic")
    widths = [max(len(row[column]) for row in [header, overall, *rows]) for column in range(len(header))]

    def line(row):
        cells = [row[0].ljust(widths[0])] + [cell.rjust(width) for cell, width in zip(row[1:], widths[1:])]
        return "  ".join(cells).rstrip()

    return "\n".join([f"Matcha, {now:%H:%M:%S}", "", line(header), *map(line, rows), "", line(overall)])


def append_csv(path, processes, now):
    path = pathlib.Path(path)
    is_new = not path.exists() or path.stat().st_size == 0
    with path.open("a", newline="", encoding="utf-8") as file:
        writer = csv.writer(file)
        if is_new:
            writer.writerow(CSV_FIELDS)
        for p in processes:
            figures = ["" if value is None else value for value in (p.cpu, p.footprint, p.peak)]
            writer.writerow([now.isoformat(timespec="seconds"), p.pid, p.kind, p.name, *figures])


def interval(text):
    value = float(text)
    if value < 1:
        raise argparse.ArgumentTypeError("une seconde au moins (le processeur se mesure sur une seconde)")
    return value


def main(argv, run=run_tool, out=sys.stdout):
    parser = argparse.ArgumentParser(description="Processeur et mémoire de Matcha, processus par processus")
    parser.add_argument("--watch", type=interval, metavar="SECONDES", help="mesure en continu, toutes les SECONDES")
    parser.add_argument("--csv", metavar="FICHIER", help="ajoute les mesures à ce fichier CSV")
    parser.add_argument("--pid", type=int, help="le Matcha de ce PID, quand plusieurs sont ouverts")
    args = parser.parse_args(argv)
    clears = bool(args.watch) and out.isatty()
    while True:
        started, now = time.monotonic(), datetime.datetime.now()
        try:
            processes = measure(run, args.pid)
        except PerfError as error:
            if not args.watch:
                print(error, file=sys.stderr)
                return 1
            text = f"Matcha, {now:%H:%M:%S}\n\n{error}"
        else:
            text = render(processes, now)
            if args.csv:
                append_csv(args.csv, processes, now)
        if clears:
            out.write("\033[H\033[2J")
        print(text, file=out, flush=True)
        if not args.watch:
            return 0
        if not clears:
            print(file=out)
        time.sleep(max(0, args.watch - (time.monotonic() - started)))


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(0)
