#!/bin/zsh
set -euo pipefail
BREW_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BREW_ROOT"
if (( $# > 1 )) || [[ -n "${1:-}" && "${1:-}" != "--standalone" ]]; then
    print -u2 "Usage: zsh scripts/package.sh [--standalone]"
    exit 2
fi
mkdir -p build dist
BREW_PACKAGE_WORK="$(mktemp -d "$BREW_ROOT/build/installer.XXXXXX")"
trap 'rm -rf "${BREW_PACKAGE_WORK:?}"' EXIT
BREW_OUTPUT_DIR="$BREW_PACKAGE_WORK/app-build" zsh scripts/build.sh "$@"
BREW_PACKAGE_APP="$BREW_PACKAGE_WORK/app-build/Brew.app"
BREW_PACKAGE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BREW_PACKAGE_APP/Contents/Info.plist")"
BREW_PACKAGE_MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$BREW_PACKAGE_APP/Contents/Info.plist")"
BREW_PACKAGE_ARCHS="$(lipo -archs "$BREW_PACKAGE_APP/Contents/MacOS/Brew")"
case "$BREW_PACKAGE_ARCHS" in
    arm64|x86_64) BREW_PACKAGE_ARCH_LABEL="$BREW_PACKAGE_ARCHS" ;;
    'arm64 x86_64'|'x86_64 arm64') BREW_PACKAGE_ARCH_LABEL=universal ;;
    *) print -u2 "Unsupported architectures: $BREW_PACKAGE_ARCHS"; exit 1 ;;
esac
BREW_PACKAGE_STEM="Brew-$BREW_PACKAGE_VERSION-$BREW_PACKAGE_ARCH_LABEL"
mkdir -p "$BREW_PACKAGE_WORK/root/Applications"
# Publish regular app files without the build machine's resource forks or ACLs.
ditto --norsrc --noextattr --noacl "$BREW_PACKAGE_APP" "$BREW_PACKAGE_WORK/root/Applications/Brew.app"
codesign --verify --deep --strict "$BREW_PACKAGE_WORK/root/Applications/Brew.app"
pkgbuild --analyze --root "$BREW_PACKAGE_WORK/root" "$BREW_PACKAGE_WORK/components.plist"
python3 - "$BREW_PACKAGE_WORK" "$BREW_PACKAGE_VERSION" "$BREW_PACKAGE_MIN_OS" "$BREW_PACKAGE_ARCHS" <<'PY'
import plistlib
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

work = Path(sys.argv[1])
version, minimum_os, architectures = sys.argv[2:]
if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", version):
    raise SystemExit("App version must contain two or three numeric components")
components = plistlib.loads((work / "components.plist").read_bytes())
if len(components) != 1 or components[0]["RootRelativeBundlePath"] != "Applications/Brew.app":
    raise SystemExit("Expected exactly one Applications/Brew.app payload")
for component in components:
    component.update(BundleIsRelocatable=False, BundleHasStrictIdentifier=True,
                     BundleIsVersionChecked=True, BundleOverwriteAction="upgrade")
(work / "components.plist").write_bytes(plistlib.dumps(components))

identifier = "io.github.flux-i.brew.installer"
distribution = ET.Element("installer-gui-script", minSpecVersion="2")
ET.SubElement(distribution, "title").text = "Brew"
ET.SubElement(distribution, "welcome", file="welcome.html", **{"mime-type": "text/html"})
ET.SubElement(distribution, "readme", file="readme.html", **{"mime-type": "text/html"})
ET.SubElement(distribution, "conclusion", file="conclusion.html", **{"mime-type": "text/html"})
ET.SubElement(distribution, "options", customize="never", **{
    "require-scripts": "false", "rootVolumeOnly": "true",
    "hostArchitectures": ",".join(architectures.split())})
ET.SubElement(distribution, "domains", enable_localSystem="true",
              enable_currentUserHome="false", enable_anywhere="false")
versions = ET.SubElement(distribution, "allowed-os-versions")
ET.SubElement(versions, "os-version", min=minimum_os)
outline = ET.SubElement(distribution, "choices-outline")
ET.SubElement(outline, "line", choice="brew")
choice = ET.SubElement(distribution, "choice", id="brew", title="Brew", visible="false")
ET.SubElement(choice, "pkg-ref", id=identifier)
reference = ET.SubElement(distribution, "pkg-ref", id=identifier, version=version, onConclusion="none")
reference.text = "Brew-component.pkg"
ET.indent(distribution)
ET.ElementTree(distribution).write(work / "Distribution.xml", encoding="utf-8", xml_declaration=True)
PY
pkgbuild --root "$BREW_PACKAGE_WORK/root" --component-plist "$BREW_PACKAGE_WORK/components.plist" \
    --identifier io.github.flux-i.brew.installer --version "$BREW_PACKAGE_VERSION" \
    --install-location / --ownership recommended "$BREW_PACKAGE_WORK/Brew-component.pkg"
BREW_PACKAGE_SIGN_ARGS=()
if [[ -n "${BREW_INSTALLER_SIGN_IDENTITY:-}" ]]; then
    BREW_PACKAGE_SIGN_ARGS=(--sign "$BREW_INSTALLER_SIGN_IDENTITY")
fi
productbuild --distribution "$BREW_PACKAGE_WORK/Distribution.xml" \
    --resources "$BREW_ROOT/Resources/Installer" --package-path "$BREW_PACKAGE_WORK" \
    "${BREW_PACKAGE_SIGN_ARGS[@]}" "$BREW_ROOT/dist/$BREW_PACKAGE_STEM.pkg"
ditto -c -k --norsrc --noextattr --noacl --keepParent \
    "$BREW_PACKAGE_WORK/root/Applications/Brew.app" "$BREW_ROOT/dist/$BREW_PACKAGE_STEM.zip"
(
    cd "$BREW_ROOT/dist"
    shasum -a 256 "$BREW_PACKAGE_STEM.pkg" "$BREW_PACKAGE_STEM.zip" > "$BREW_PACKAGE_STEM-SHA256SUMS.txt"
)
print "Installer: $BREW_ROOT/dist/$BREW_PACKAGE_STEM.pkg"
print "App ZIP: $BREW_ROOT/dist/$BREW_PACKAGE_STEM.zip"
print "Checksums: $BREW_ROOT/dist/$BREW_PACKAGE_STEM-SHA256SUMS.txt"
