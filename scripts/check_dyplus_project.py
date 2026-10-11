#!/usr/bin/env python3
"""Regression guards for known risks; not a substitute for runtime/security review."""
from pathlib import Path
import re
import sys
import hashlib

root = Path(__file__).resolve().parents[1]
sources = root / "Sources/DYPlus"
paths = sorted(p for p in sources.rglob("*") if p.suffix in {".m", ".mm", ".xm", ".c", ".h"})
contents = {p: p.read_text() for p in paths}
errors = []
def demand(condition, message):
    if not condition:
        errors.append(message)

for path, text in contents.items():
    relative = path.relative_to(root)
    for expression, reason in [
        (r"unarchiveObjectWithData\s*:", "use secure class-whitelisted unarchiving"),
        (r"performSelector\s*:\s*@selector\(isPaused\)", "BOOL cannot be treated as an Objective-C object"),
        (r"\bonceToken\s*=\s*0\s*;", "dispatch_once tokens cannot be reset"),
        (r'removeItemAtPath\s*:\s*plistPath', "never delete host preference plist"),
        (r'DYYYBlockAllAds', "removed dead/duplicate ad setting"),
        (r'NSString\s*\*\s*\w+\s*=\s*\[\[NSUserDefaults standardUserDefaults\] objectForKey:@"DYYY', "use type-safe string preference reads"),
    ]:
        demand(not re.search(expression, text), f"{relative}: {reason}")

makefile = (root / "Makefile").read_text()
modules = (root / "Build/DYPlusModules.mk").read_text()
control = (root / "control").read_text()
branding = (sources / "Settings/DYPlusBranding.h").read_text()
demand("DYPLUS_RELEASE ?= 1" in makefile, "daily/default build must exclude developer tooling")
demand("PACKAGE_VERSION = 0.1" in makefile and "Version: 0.1" in control and '@"0.1"' in branding, "version metadata must agree")
demand("Name: DouYinPlus" in control and "Author: xiaoleGun" in control and '@"DouYinPlus"' in branding, "public package/title must remain DouYinPlus")
demand("firmware (>= 15.0)" in control, "package minimum OS must match target 15.0")
units = re.findall(r"Sources/[\w/]+\.(?:xm|mm|m|c)\b", modules)
demand(len(units) == len(set(units)), "source units must not be compiled twice")
for unit in units:
    demand((root / unit).is_file(), f"missing build input {unit}")
frameworks = re.search(r"^\$\(TWEAK_NAME\)_FRAMEWORKS = (.+)$", makefile, re.M).group(1).split()
demand(not {"SwiftUI", "Combine", "Metal", "MetalKit", "Security", "CoreImage"}.intersection(frameworks), "unused frameworks must remain debug-only")
spoof = contents[sources / "Integration/System/DYPlusSystemVersionSpoof.xm"]
demand("%hook NSProcessInfo" not in spoof, "preserve actual OS capability tests")
demand("return YES" not in spoof, "never claim every OS version is supported")
backup = contents[sources / "Settings/DYPlusSettingViewControllerBackup.m"]
demand("DYPlusSettingsArchive decodeData" in backup and "DYPlusSettingsIOQueue()" in backup, "restore must validate on a serial I/O queue")
download = contents[sources / "Services/Media/DYPlusManagerDownload.m"]
demand("DYPlusDownloadResponse(data, &jsonError)" in download, "third-party download JSON must validate resource types")
demand("NSTemporaryDirectory()" not in backup and '@"BDByteCast"' not in backup, "clean only plugin-owned temporary files")
crash = contents[sources / "Diagnostics/DYPlusCrashCatcher.m"]
handler = crash.split("static void DYPlusSignalHandler(int sig)", 1)[1].split("// 未捕获 ObjC", 1)[0]
demand("backtrace(" not in handler and "snprintf(" not in handler, "fatal signal handler must not format/unwind")
demand("DYPlusCrashLogNames(dir)" in crash, "retention must exclude unrelated logs/databases")
header = contents[sources / "Integration/System/DYPlusABTestHook.h"]
extern_block = header.split('extern "C" {', 1)[1].split("\n}", 1)[0]
demand("getCurrentABTestData" in extern_block and "loadFixedABTestData" in extern_block, "C/ObjC++ interface linkage must agree")

# Active namespace/import/build-order regression guards.
build_order_hash = hashlib.sha256("\n".join(units).encode()).hexdigest()
demand(build_order_hash == "7ad4fd441f9ecd3227c009b44fd1732eb6742d72db1bd8c25c31cc95c28e897a", "preserve the original 105-unit hook registration order")
demand(all(path.name.startswith("DYPlus") for path in paths), "owned source/header filenames must use DYPlus")
strip = re.compile(r'//[^\n]*|/\*[\s\S]*?\*/|@?"(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27')
for path, text in contents.items():
    code = strip.sub("", text)
    stale = [token for token in re.findall(r"\b(?:DYYY|DYP|dyyy)\w*\b", code)
             if not token.startswith(("DYYYFLEX", "DYYYFHS")) and token not in {"DYYY_FLEX", "DYYYDatabaseManager"}
             and not token.startswith(("DYPlus", "DYPLUS_"))]
    demand(not stale, f"{path.relative_to(root)}: stale owned identifiers {sorted(set(stale))}")
    for name in re.findall(r'^\s*#\s*(?:import|include)\s*"([^"]+)"', text, re.M):
        if name.startswith(tuple(module + "/" for module in ("Core", "Integration", "Features", "Services", "Settings", "UI", "Audio", "Diagnostics"))):
            demand((sources / name).is_file(), f"{path.relative_to(root)}: missing module include {name}")
demand("Package: com.xiaolegun.douyinplus" in control and "PACKAGE_IDENTIFIER = com.xiaolegun.douyinplus" in makefile, "preserve public package identity")
demand("TWEAK_NAME = DYPlus" in makefile, "internal binary/module namespace must be DYPlus")
legacy_values = {value for text in contents.values() for value in re.findall(r'@"((?:DYYY|DYKiller)[A-Za-z0-9_]*)"', text)}
legacy_values_hash = hashlib.sha256("\n".join(sorted(legacy_values)).encode()).hexdigest()
demand(legacy_values_hash == "aa11f0b68e6db63a78d3cd85dfeca97d132c4a4dd6a833ba998426ab3d0150f7", "preserve legacy preference/event/path identifiers; review changes before updating this baseline")

lines = sum(text.count("\n") for text in contents.values())
if errors:
    print("\n".join(f"FAIL: {message}" for message in errors), file=sys.stderr)
    sys.exit(1)
print(f"Project guards OK: {len(paths)} owned source/header files, {lines} lines, {len(units)} build units, {len(frameworks)} explicit release frameworks.")
print("Scope: known-pattern regression checks only; no claim of complete security proof.")
