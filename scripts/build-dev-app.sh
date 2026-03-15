#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Masko Code"
EXEC_NAME="masko-code"
DERIVED_DATA="${DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData}"
EXEC_PATH="$(find "$DERIVED_DATA" -path "*/Build/Products/Debug/$EXEC_NAME" -type f 2>/dev/null | head -n 1)"
EXEC_DIR="$(dirname "$EXEC_PATH")"
SPARKLE_FRAMEWORK="$EXEC_DIR/Sparkle.framework"
RESOURCE_BUNDLE="$EXEC_DIR/${EXEC_NAME}_masko-code.bundle"
SIGN_IDENTITY="${MASKO_CODESIGN_IDENTITY:-}"

if [[ -z "$EXEC_PATH" ]]; then
  echo "Could not find Xcode debug executable. Build and run the project from Xcode first." >&2
  exit 1
fi

if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
  echo "Could not find Sparkle.framework next to the debug executable." >&2
  echo "Open the project in Xcode and build it once so package frameworks are produced." >&2
  exit 1
fi

if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "Could not find SwiftPM resource bundle next to the debug executable." >&2
  echo "Open the project in Xcode and build it once so resources are produced." >&2
  exit 1
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>&1 | sed -n 's/.*\"\\(.*\\)\"/\\1/p' | head -n 1)"
fi

OUT_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$OUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
LIB_DIR="$CONTENTS_DIR/lib"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$LIB_DIR"

rm -f "$MACOS_DIR/$EXEC_NAME"
rm -rf "$LIB_DIR/Sparkle.framework"
rm -rf "$RESOURCES_DIR/$(basename "$RESOURCE_BUNDLE")"

cp "$EXEC_PATH" "$MACOS_DIR/$EXEC_NAME"
cp -R "$SPARKLE_FRAMEWORK" "$LIB_DIR/Sparkle.framework"
cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
rm -rf "$RESOURCES_DIR/Fonts" "$RESOURCES_DIR/Images" "$RESOURCES_DIR/Defaults" "$RESOURCES_DIR/Extensions"
cp -R "$ROOT_DIR/Sources/Resources/Fonts" "$RESOURCES_DIR/"
cp -R "$ROOT_DIR/Sources/Resources/Images" "$RESOURCES_DIR/"
cp -R "$ROOT_DIR/Sources/Resources/Defaults" "$RESOURCES_DIR/"
cp -R "$ROOT_DIR/Sources/Resources/Extensions" "$RESOURCES_DIR/"

chmod +x "$MACOS_DIR/$EXEC_NAME"

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --deep --sign "$SIGN_IDENTITY" --timestamp=none "$APP_BUNDLE" >/dev/null
else
  codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
fi

echo "Built stable dev app bundle:"
echo "$APP_BUNDLE"
echo
if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "Signed with:"
  echo "$SIGN_IDENTITY"
else
  echo "Signed ad-hoc (no local code-signing identity found)."
  echo "Accessibility trust may be unstable until you sign with a stable identity."
fi
echo
echo "Grant Accessibility/Notifications to this .app once, then rebuild this same bundle after code changes."
echo "The bundle path stays stable, so you should not need to re-grant permissions after each rebuild."
echo
echo "Open it with:"
echo "open \"$APP_BUNDLE\""
