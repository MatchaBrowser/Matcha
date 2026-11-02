"""Tests of perf.py (task 11.1): the processes of Matcha's coalition and their groups, their figures from `footprint`
and `top`, several Matcha open, the table and the CSV file. The tools' outputs are copied from a real session.

    python3 -I scripts/test-perf.py

Run by scripts/check.sh. Depends only on Python.
"""

import contextlib
import datetime
import importlib.util
import io
import json
import pathlib
import sys
import tempfile
import unittest

# Loaded from its path (`-I` leaves the script's folder out of the import path), leaving no `__pycache__` there; known
# to `sys.modules`, where Python 3.9's dataclasses look for their module.
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("perf", pathlib.Path(__file__).with_name("perf.py"))
perf = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = perf
SPEC.loader.exec_module(perf)

LISTING = """\
21) "Matcha" ASN:0x0-0x1e01e:
    bundleID="com.matchabrowser.matcha"
    bundle path="/Applications/Matcha.app"
    executable path="/Applications/Matcha.app/Contents/MacOS/Matcha"
    pid = 792 type="Foreground" flavor=3 Version="128" fileType="APPL" Arch=ARM64 sandboxed
    coalition: 933  { 792 961 962 966 6434 7862 11051 11470 49644 }
    parentASN="loginwindow" ASN:0x0-0x3003:
22) "Safari" ASN:0x0-0x2a02a:
    bundleID="com.apple.Safari"
    bundle path="/Applications/Safari.app"
    pid = 900 type="Foreground" flavor=3 Version="21624" fileType="APPL" Arch=ARM64 sandboxed
    coalition: 940  { 900 901 }
39) "Matcha Networking" ASN:0x0-0x34034:
    bundleID="com.apple.WebKit.Networking"
    pid = 961 !cgsConnection !signalled type="UIElement" flavor=[ NULL ]  Version="21624.5.1.11.3" fileType="XPC!"
    childASNs: ASN:0x0-0x37037: ASN:0x0-0x5bc5bc:
40) "Matcha Graphics and Media" ASN:0x0-0x35035:
    bundleID="com.apple.WebKit.GPU"
    pid = 962 !cgsConnection !signalled type="UIElement" flavor=[ NULL ]  Version="21624.5.1.11.3" fileType="XPC!"
41) "Bitwarden Web Extension" ASN:0x0-0x37037:
    bundleID="com.apple.WebKit.WebContent"
    bundle path=[ NULL ]
    pid = 966 !cgsConnection !signalled type="UIElement" flavor=[ NULL ]  Version="21624.5.1.11.3" fileType="XPC!"
    parentASN="Matcha Networking" ASN:0x0-0x34034:
45) "github.com" ASN:0x0-0x45045:
    bundleID="com.apple.WebKit.WebContent"
    pid = 901 !cgsConnection !signalled type="UIElement" flavor=[ NULL ]  Version="21624.5.1.11.3" fileType="XPC!"
50) "MatchaUITests-Runner" ASN:0x0-0x50050:
    bundleID="com.matchabrowser.MatchaUITests.xctrunner"
    pid = 1200 type="Foreground" flavor=3 fileType="APPL" Arch=ARM64
67) "AutoFill (Matcha)" ASN:0x0-0x591591:
    bundleID="com.apple.SafariPlatformSupport.Helper"
    pid = 49644 type="BackgroundOnly" flavor=2 Version="21624.5.1.11.3" fileType="XPC!" Arch=ARM64 sandboxed
70) "Matcha Web Content" ASN:0x0-0x5bc5bc:
    bundleID="com.apple.WebKit.WebContent"
    bundle path=[ NULL ]
    pid = 11051 !cgsConnection !signalled type="UIElement" flavor=[ NULL ]  Version="21624.5.1.11.3" fileType="XPC!"
    parentASN="Matcha Networking" ASN:0x0-0x34034:
72) "Matcha Web Content" ASN:0x0-0x5d65d6:
    bundleID="com.apple.WebKit.WebContent"
    pid = 6434 !cgsConnection !signalled type="UIElement" flavor=[ NULL ]  Version="21624.5.1.11.3" fileType="XPC!"
"""

# The same, with a second Matcha open (a Debug build); its coalition only has itself.
SECOND = """\
80) "Matcha" ASN:0x0-0x80080:
    bundleID="com.matchabrowser.matcha"
    bundle path="/Users/me/matcha/build/Build/Products/Debug/Matcha.app"
    pid = 5000 type="Foreground" flavor=3 Version="128" fileType="APPL" Arch=ARM64 sandboxed
    coalition: 960  { 5000 }
"""

WEBKIT = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices"
PS = f"""\
  792 /Applications/Matcha.app/Contents/MacOS/Matcha
  961 {WEBKIT}/com.apple.WebKit.Networking.xpc/Contents/MacOS/com.apple.WebKit.Networking
  962 {WEBKIT}/com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU
  966 {WEBKIT}/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent
 5000 /Users/me/matcha/build/Build/Products/Debug/Matcha.app/Contents/MacOS/Matcha
 6434 {WEBKIT}/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent
 7862 {WEBKIT}/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent
11051 {WEBKIT}/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent
11470 /System/Library/Frameworks/VideoToolbox.framework/Versions/A/XPCServices/VTDecoderXPCService.xpc/Contents/MacOS/VTDecoderXPCService
49644 /System/Library/PrivateFrameworks/SafariPlatformSupport.framework/Versions/A/XPCServices/com.apple.SafariPlatformSupport.Helper.xpc/Contents/MacOS/com.apple.SafariPlatformSupport.Helper
"""

MIB = 1 << 20
FOOTPRINTS = {
    792: (187 * MIB, 822 * MIB),
    961: (19 * MIB, 95 * MIB),
    962: (67 * MIB, 403 * MIB),
    966: (194 * MIB, 202 * MIB),
    5000: (150 * MIB, 160 * MIB),
    6434: (147 * MIB, 328 * MIB),
    7862: (7_759_462, 9_017_753),
    11051: (785 * MIB, 1_932_735_283),
    11470: (4_508_877, 27 * MIB),
    49644: (12 * MIB, 14 * MIB),
}

# `top -l 2`: the first sample's figures are not over an interval, only the second one counts.
TOP = """\
Processes: 802 total, 3 running, 799 sleeping, 4191 threads
PhysMem: 46G used (4258M wired, 2222M compressor), 1602M unused.

PID    %CPU
792    9.9
11051  9.9
Processes: 802 total, 3 running, 799 sleeping, 4191 threads
PhysMem: 46G used (4258M wired, 2222M compressor), 1602M unused.

PID    %CPU
792    12.5
11051  104.2
962    3.1
961    0.0
966    0.4
6434   0.0
7862   0.0
11470  0.0
49644  0.0
5000   1.0
"""

NOW = datetime.datetime(2026, 11, 1, 23, 19, 47)


class Tools:
    """The macOS tools perf.py calls, answering with the outputs above."""

    def __init__(self, listing=LISTING, ps=PS, top=TOP, footprints=None):
        self.listing, self.ps, self.top = listing, ps, top
        self.footprints = FOOTPRINTS if footprints is None else footprints
        self.calls = []

    def __call__(self, arguments):
        self.calls.append(arguments)
        tool = arguments[0]
        if tool == "footprint":
            pids = [int(argument) for argument in arguments if argument.isdigit()]
            processes = [
                {"name": "?", "pid": pid, "footprint": self.footprints[pid][0],
                 "auxiliary": {"phys_footprint": self.footprints[pid][0], "phys_footprint_peak": self.footprints[pid][1]}}
                for pid in pids if pid in self.footprints
            ]
            report = arguments[arguments.index("--json") + 1]
            pathlib.Path(report).write_text(json.dumps({"unit": "byte", "processes": processes}))
            return ""
        if tool == "ps":
            asked = {int(pid) for pid in arguments[-1].split(",")}
            return "".join(line + "\n" for line in self.ps.splitlines() if int(line.split()[0]) in asked)
        return {"lsappinfo": self.listing, "top": self.top}[tool]


def by_pid(processes):
    return {process.pid: process for process in processes}


class PerfTests(unittest.TestCase):
    def test_the_coalition_gives_the_processes_and_their_groups(self):
        processes = by_pid(perf.measure(Tools()))
        self.assertEqual(
            {pid: (process.kind, process.name) for pid, process in processes.items()},
            {
                792: ("app", "Matcha"),
                961: ("network", "Matcha Networking"),
                962: ("gpu", "Matcha Graphics and Media"),
                966: ("extensions", "Bitwarden Web Extension"),
                6434: ("pages", "Matcha Web Content"),
                7862: ("pages", "com.apple.WebKit.WebContent"),
                11051: ("pages", "Matcha Web Content"),
                11470: ("other", "VTDecoderXPCService (décodage vidéo)"),
                49644: ("other", "AutoFill (Matcha)"),
            },
        )

    def test_memory_comes_from_footprint_and_the_processor_from_the_last_sample_of_top(self):
        tools = Tools()
        pages = by_pid(perf.measure(tools))[11051]
        self.assertEqual((pages.footprint, pages.peak, pages.cpu), (785 * MIB, 1_932_735_283, 104.2))
        [top] = [call for call in tools.calls if call[0] == "top"]
        self.assertEqual(top[:3], ["top", "-l", "2"])
        self.assertEqual(top.count("-pid"), 9)

    def test_a_process_that_ended_is_left_out_and_one_without_figures_is_kept(self):
        ps = "".join(line + "\n" for line in PS.splitlines() if not line.lstrip().startswith("7862 "))
        footprints = {pid: figures for pid, figures in FOOTPRINTS.items() if pid != 961}
        processes = by_pid(perf.measure(Tools(ps=ps, footprints=footprints)))
        self.assertNotIn(7862, processes)
        self.assertEqual((processes[961].footprint, processes[961].peak), (None, None))
        [network] = [line for line in perf.render(processes.values(), NOW).splitlines() if " 961 " in line]
        self.assertEqual(network.split(), ["Matcha", "Networking", "961", "0,0", "%", "—", "—"])

    def test_without_matcha_the_measure_says_so(self):
        without = LISTING[LISTING.index('22) "Safari"') :]
        with self.assertRaisesRegex(perf.PerfError, "Matcha n'est pas ouvert"):
            perf.measure(Tools(listing=without))

    def test_with_several_matcha_a_pid_chooses_which_one(self):
        tools = Tools(listing=LISTING + SECOND)
        with self.assertRaises(perf.PerfError) as raised:
            perf.measure(tools)
        self.assertIn("--pid 792   /Applications/Matcha.app", str(raised.exception))
        self.assertIn("--pid 5000   /Users/me/matcha/build/Build/Products/Debug/Matcha.app", str(raised.exception))
        self.assertEqual(list(by_pid(perf.measure(tools, pid=5000))), [5000])
        with self.assertRaisesRegex(perf.PerfError, "Aucun Matcha ouvert n'a le PID 42"):
            perf.measure(tools, pid=42)

    def test_the_table_has_a_total_per_group_and_the_largest_processes_first(self):
        lines = perf.render(perf.measure(Tools()), NOW).splitlines()
        self.assertEqual(lines[0], "Matcha, 23:19:47")
        self.assertEqual(lines[2].split(), ["PID", "Processeur", "Mémoire", "Pic"])
        self.assertEqual(
            [line.split("  ")[0].strip() for line in lines if line and not line.startswith(" ")][1:],
            ["App", "Pages (3)", "Extensions", "Réseau", "Graphisme et médias", "Autres (2)", "Total (9 processus)"],
        )
        pages = lines.index(next(line for line in lines if line.startswith("Pages")))
        self.assertTrue(lines[pages].endswith("104,2 %   939 Mo"))
        self.assertTrue(lines[pages + 1].endswith("11051     104,2 %   785 Mo  1,8 Go"))
        self.assertTrue(lines[pages + 3].endswith("7862       0,0 %   7,4 Mo  8,6 Mo"))
        self.assertTrue(lines[-1].endswith("120,2 %   1,4 Go"))

    def test_memory_is_shown_in_binary_units_with_a_decimal_comma(self):
        self.assertEqual(perf.format_memory(187 * MIB), "187 Mo")
        self.assertEqual(perf.format_memory(int(1.5 * (1 << 30))), "1,5 Go")
        self.assertEqual(perf.format_memory(int(9.5 * MIB)), "9,5 Mo")
        self.assertEqual(perf.format_memory(800), "800 o")
        self.assertEqual(perf.format_memory(None), "—")
        self.assertEqual(perf.format_processor(12.34), "12,3 %")

    def test_the_csv_file_gets_its_header_once_and_a_row_per_process(self):
        with tempfile.TemporaryDirectory() as folder:
            path = pathlib.Path(folder) / "perf.csv"
            processes = perf.measure(Tools())
            perf.append_csv(path, processes, NOW)
            perf.append_csv(path, processes, NOW + datetime.timedelta(seconds=5))
            rows = path.read_text(encoding="utf-8").splitlines()
        self.assertEqual(rows[0], ",".join(perf.CSV_FIELDS))
        self.assertEqual(len(rows), 1 + 2 * len(processes))
        self.assertIn(f"2026-11-01T23:19:47,11051,pages,Matcha Web Content,104.2,{785 * MIB},1932735283", rows)
        self.assertIn("2026-11-01T23:19:52,792,app,Matcha,12.5,196083712,861929472", rows)

    def test_main_prints_the_table_or_the_error(self):
        out = io.StringIO()
        self.assertEqual(perf.main([], run=Tools(), out=out), 0)
        self.assertIn("Total (9 processus)", out.getvalue())
        errors = io.StringIO()
        with contextlib.redirect_stderr(errors):
            self.assertEqual(perf.main([], run=Tools(listing=""), out=io.StringIO()), 1)
        self.assertEqual(errors.getvalue(), "Matcha n'est pas ouvert.\n")


if __name__ == "__main__":
    unittest.main()
