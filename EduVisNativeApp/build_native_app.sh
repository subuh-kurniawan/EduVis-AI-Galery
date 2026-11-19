#!/usr/bin/env bash
set -e

# ==============================================================================
# Script Pembangun Aplikasi Native macOS (SwiftUI) EduVis Native AI
# Mengompilasi seluruh 13 Workspace, Voice Engine, Document Analyzer, dsb.
# Membangun secara atomik di staging directory sebelum dipindahkan ke bundle final
# sehingga Finder & LaunchServices tidak pernah melihat bundel setengah jadi.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_NAME="EduVis Native AI"
BUNDLE_DIR="${SCRIPT_DIR}/${APP_NAME}.app"
STAGE_PARENT="${SCRIPT_DIR}/.build_stage"
STAGE_DIR="${STAGE_PARENT}/${APP_NAME}.app"
CONTENTS_DIR="${STAGE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

echo "==> Menyiapkan staging bundle atomik: ${STAGE_DIR}"
rm -rf "${STAGE_PARENT}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${FRAMEWORKS_DIR}"
mkdir -p "${RESOURCES_DIR}"

echo "==> Menulis Info.plist & PkgInfo lebih awal..."
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>id</string>
    <key>CFBundleExecutable</key>
    <string>EduVisNativeAI</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIdentifier</key>
    <string>com.eduvis.native-ai</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>EduVis Native AI</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>EduVis Native AI memerlukan akses mikrofon untuk fitur EduVis Live Voice dan pendiktean suara.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>EduVis Native AI memerlukan pengenalan suara untuk mengubah ucapan menjadi instruksi AI.</string>
</dict>
</plist>
EOF
printf 'APPL????' > "${CONTENTS_DIR}/PkgInfo"

if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

SWIFTC_CMD="xcrun swiftc"
SDK_PATH="$(xcrun --show-sdk-path --sdk macosx)"

echo "==> Mengompilasi seluruh modul SwiftUI Native..."
${SWIFTC_CMD} \
    -disable-sandbox \
    -module-cache-path /tmp/eduvis-xcode-module-cache \
    -sdk "${SDK_PATH}" \
    -target arm64-apple-macosx14.0 \
    -parse-as-library \
    -O \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    "${SCRIPT_DIR}"/EduVisNativeApp.swift \
    "${SCRIPT_DIR}"/ContentView.swift \
    "${SCRIPT_DIR}"/SidebarView.swift \
    "${SCRIPT_DIR}"/ChatViews.swift \
    "${SCRIPT_DIR}"/AIResponseRendererView.swift \
    "${SCRIPT_DIR}"/WorkspacesViews.swift \
    "${SCRIPT_DIR}"/WorkspaceWebView.swift \
    "${SCRIPT_DIR}"/FeatureModalsAndInspectorView.swift \
    "${SCRIPT_DIR}"/QuickAskModalView.swift \
    "${SCRIPT_DIR}"/SettingsSheet.swift \
    "${SCRIPT_DIR}"/LocalAIService.swift \
    "${SCRIPT_DIR}"/NativeLiteRTEngine.swift \
    "${SCRIPT_DIR}"/SpeechRecognizerService.swift \
    "${SCRIPT_DIR}"/SystemMonitorService.swift \
    "${SCRIPT_DIR}"/DocumentAnalyzerService.swift \
    "${SCRIPT_DIR}"/SessionExportImportManager.swift \
    "${SCRIPT_DIR}"/Models.swift \
    "${SCRIPT_DIR}"/MarkdownParser.swift \
    "${SCRIPT_DIR}"/LiquidGlassModifier.swift \
    -o "${MACOS_DIR}/EduVisNativeAI"
chmod 755 "${MACOS_DIR}/EduVisNativeAI"

echo "==> Membundel pustaka native LiteRT-LM (liblitert-lm.dylib)..."
LITERT_DYLIB=""
for candidate in \
    "/Library/Frameworks/Python.framework/Versions/3.14/lib/python3.14/site-packages/litert_lm/liblitert-lm.dylib" \
    "/Library/Frameworks/Python.framework/Versions/Current/lib/python3.14/site-packages/litert_lm/liblitert-lm.dylib" \
    "${HOME}/Library/Application Support/Gemma AI Gallery/litert-lm-venv/lib/python3.14/site-packages/litert_lm/liblitert-lm.dylib"
do
    if [ -f "${candidate}" ]; then
        LITERT_DYLIB="${candidate}"
        break
    fi
done
if [ -z "${LITERT_DYLIB}" ]; then
    LITERT_DYLIB="$(/Library/Frameworks/Python.framework/Versions/3.14/bin/python3 -c 'import litert_lm, pathlib; print(pathlib.Path(litert_lm.__file__).parent / "liblitert-lm.dylib")' 2>/dev/null || true)"
fi
if [ -n "${LITERT_DYLIB}" ] && [ -f "${LITERT_DYLIB}" ]; then
    cp "${LITERT_DYLIB}" "${FRAMEWORKS_DIR}/liblitert-lm.dylib"
    chmod 755 "${FRAMEWORKS_DIR}/liblitert-lm.dylib"
    xattr -cr "${FRAMEWORKS_DIR}/liblitert-lm.dylib" 2>/dev/null || true
    codesign --force --sign - "${FRAMEWORKS_DIR}/liblitert-lm.dylib"
    echo "    -> Dibundel & ditandatangani: ${FRAMEWORKS_DIR}/liblitert-lm.dylib"
fi

echo "==> Menyalin aset & ikon..."
if [ -f "${PROJECT_DIR}/nano_asset/app_icon.png" ]; then
    cp "${PROJECT_DIR}/nano_asset/app_icon.png" "${RESOURCES_DIR}/AppIcon.png"
fi
if [ -f "${PROJECT_DIR}/nano_asset/dev.jpeg" ]; then
    cp "${PROJECT_DIR}/nano_asset/dev.jpeg" "${RESOURCES_DIR}/dev.jpeg"
fi
if [ -f "${PROJECT_DIR}/EduVis AI Gallery.app/Contents/Resources/EduVisAIGallery.icns" ]; then
    cp "${PROJECT_DIR}/EduVis AI Gallery.app/Contents/Resources/EduVisAIGallery.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

echo "==> Membundel runtime web & backend Python (self-contained)..."
python3 -c 'import sys; from pathlib import Path; sys.path.insert(0, str(Path(sys.argv[1]) / "scripts")); import build_dmg; build_dmg.copy_project_runtime(Path(sys.argv[2]) / "app")' "${PROJECT_DIR}" "${RESOURCES_DIR}"

echo "==> Menormalkan izin berkas & menandatangani bundle (ad-hoc)..."
chmod -R u+rwX,go+rX,go-w "${STAGE_DIR}"
xattr -cr "${STAGE_DIR}" 2>/dev/null || true
codesign --force --deep --sign - "${STAGE_DIR}"

echo "==> Memindahkan bundle secara atomik ke: ${BUNDLE_DIR}"
rm -rf "${BUNDLE_DIR}"
mv "${STAGE_DIR}" "${BUNDLE_DIR}"
rm -rf "${STAGE_PARENT}"
touch "${BUNDLE_DIR}"

if [ -x "${LSREGISTER}" ]; then
    echo "==> Mendaftarkan ke macOS LaunchServices..."
    "${LSREGISTER}" -f "${BUNDLE_DIR}" || true
fi

echo "=============================================================================="
echo " Berhasil! Aplikasi native macOS komprehensif siap:"
echo " ${BUNDLE_DIR}"
echo "=============================================================================="
