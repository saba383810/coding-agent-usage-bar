#!/bin/bash
# ビルドして /Applications にインストールし、起動する。
# 更新したい時もこのスクリプトを再実行するだけでよい。
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="CodingAgentUsageBar"
BUILT="build/${APP_NAME}.app"
DEST="/Applications/${APP_NAME}.app"
EXEC_PATH="${APP_NAME}.app/Contents/MacOS/${APP_NAME}"

./build.sh

# 起動中のままだと差し替えに失敗するので、先に終了させる
if pgrep -f "$EXEC_PATH" >/dev/null 2>&1; then
    echo "起動中の ${APP_NAME} を終了します"
    pkill -f "$EXEC_PATH" || true
    for _ in $(seq 1 25); do
        pgrep -f "$EXEC_PATH" >/dev/null 2>&1 || break
        sleep 0.2
    done
fi

if [ -d "$DEST" ] && ! rm -rf "$DEST" 2>/dev/null; then
    echo "既存の ${DEST} を削除できませんでした。権限を確認してください:" >&2
    echo "  sudo rm -rf \"$DEST\"" >&2
    exit 1
fi

if ! cp -R "$BUILT" "$DEST" 2>/dev/null; then
    echo "${DEST} にコピーできませんでした。権限を確認してください:" >&2
    echo "  sudo cp -R \"$BUILT\" \"$DEST\"" >&2
    exit 1
fi

open "$DEST"

echo
echo "インストールしました: $DEST"
echo "ログイン時に自動起動したい場合は、メニューバーのアイコン → 歯車 →"
echo "「ログイン時に起動」を ON にしてください。"
