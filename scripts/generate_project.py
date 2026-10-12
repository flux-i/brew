#!/usr/bin/env python3
"""Generate a dependency-free Xcode project from the app's actual Swift files."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
project = root / "Brew.xcodeproj"
project.mkdir(exist_ok=True)
objects = {}

def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def obj(name, value):
    identifier = uid(name)
    objects[identifier] = value
    return identifier

def quote(value):
    return json.dumps(str(value), ensure_ascii=False)

swift = sorted(root.glob("Sources/**/*.swift"))
resources = [root / "Resources/Brew.sdef", root / "Resources/Brew.icns"]
source_refs, resource_refs, source_builds, resource_builds = [], [], [], []
for path in swift + resources:
    relative = path.relative_to(root).as_posix()
    filetype = "sourcecode.swift" if path.suffix == ".swift" else "file"
    ref = obj("file:" + relative, f"{{isa = PBXFileReference; lastKnownFileType = {filetype}; path = {quote(relative)}; sourceTree = SOURCE_ROOT;}}")
    build = obj("build:" + relative, f"{{isa = PBXBuildFile; fileRef = {ref};}}")
    if path in swift:
        source_refs.append(ref); source_builds.append(build)
    else:
        resource_refs.append(ref); resource_builds.append(build)
info = obj("info", '{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Resources/Info.plist; sourceTree = SOURCE_ROOT;}')
product = obj("product", '{isa = PBXFileReference; explicitFileType = wrapper.application; path = Brew.app; sourceTree = BUILT_PRODUCTS_DIR;}')
sources = obj("sources", "{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (" + ",".join(source_builds) + "); runOnlyForDeploymentPostprocessing = 0;}")
res = obj("resources", "{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (" + ",".join(resource_builds) + "); runOnlyForDeploymentPostprocessing = 0;}")
frameworks = obj("frameworks", '{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;}')
source_group = obj("source_group", "{isa = PBXGroup; name = Sources; children = (" + ",".join(source_refs) + "); sourceTree = \"<group>\";}")
resource_group = obj("resource_group", "{isa = PBXGroup; name = Resources; children = (" + ",".join(resource_refs + [info]) + "); sourceTree = \"<group>\";}")
products = obj("products", f'{{isa = PBXGroup; name = Products; children = ({product}); sourceTree = "<group>";}}')
main_group = obj("main_group", f'{{isa = PBXGroup; children = ({source_group}, {resource_group}, {products}); sourceTree = "<group>";}}')
project_configs, target_configs = [], []
for name in ["Debug", "Release"]:
    project_configs.append(obj("project_config:" + name, f'{{isa = XCBuildConfiguration; name = {name}; buildSettings = {{SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 13.0; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES;}};}}'))
    settings = {
        "PRODUCT_NAME": "Brew", "PRODUCT_BUNDLE_IDENTIFIER": "app.local.brew",
        "INFOPLIST_FILE": "Resources/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
        "CODE_SIGN_STYLE": "Manual", "CODE_SIGN_IDENTITY": "-", "ENABLE_HARDENED_RUNTIME": "YES",
        "COMBINE_HIDPI_IMAGES": "YES", "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if name == "Debug" else "-O",
        "SWIFT_COMPILATION_MODE": "singlefile" if name == "Debug" else "wholemodule",
        "DEBUG_INFORMATION_FORMAT": "dwarf" if name == "Debug" else "dwarf-with-dsym",
    }
    body = " ".join(f"{key} = {quote(value)};" for key, value in settings.items())
    target_configs.append(obj("target_config:" + name, f"{{isa = XCBuildConfiguration; name = {name}; buildSettings = {{{body}}};}}"))
pc = obj("project_config_list", "{isa = XCConfigurationList; buildConfigurations = (" + ",".join(project_configs) + "); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}")
tc = obj("target_config_list", "{isa = XCConfigurationList; buildConfigurations = (" + ",".join(target_configs) + "); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}")
target = obj("target", f'{{isa = PBXNativeTarget; name = Brew; productName = Brew; buildConfigurationList = {tc}; buildPhases = ({sources}, {frameworks}, {res}); buildRules = (); dependencies = (); productReference = {product}; productType = "com.apple.product-type.application";}}')
pr = obj("project", f'{{isa = PBXProject; attributes = {{LastUpgradeCheck = 2700;}}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, Base); mainGroup = {main_group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target});}}')
body = "\n".join(f"\t\t{key} = {value};" for key, value in objects.items())
(project / "project.pbxproj").write_text(f"// !$*UTF8*$!\n{{archiveVersion = 1; classes = {{}}; objectVersion = 56; objects = {{\n{body}\n}}; rootObject = {pr};}}\n")
schemes = project / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
ref_xml = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Brew.app" BlueprintName="Brew" ReferencedContainer="container:Brew.xcodeproj"/>'
(schemes / "Brew.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref_xml}</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref_xml}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release"><BuildableProductRunnable runnableDebuggingMode="0">{ref_xml}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print("Generated Brew.xcodeproj")
