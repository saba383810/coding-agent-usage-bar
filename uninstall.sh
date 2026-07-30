#!/bin/bash
# /Applications からアンインストールする。
# --purge を付けると設定 (UserDefaults) も消す。
set -euo pipefail

APP_NAME="CodingAgentUsageBar"
BUNDLE_ID="io.saba383810.CodingAgentUsageBar"
DEST="/Applications/${APP_NAME}.app"
EXEC_PATH="${APP_NAME}.app/Contents/MacOS/${APP_NAME}"
PURGE=false

for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=true ;;
        *) echo "使い方: $0 [--purge]" >&2; exit 1 ;;
    esac
done

if pgrep -f "$EXEC_PATH" >/dev/null 2>&1; then
    echo "起動中の ${APP_NAME} を終了します"
    pkill -f "$EXEC_PATH" || true
    for _ in $(seq 1 25); do
        pgrep -f "$EXEC_PATH" >/dev/null 2>&1 || break
        sleep 0.2
    done
fi

# ログイン項目の登録はアプリ自身しか解除できないため、専用の引数で起動して解除させる
if [ -d "$DEST" ]; then
    echo "ログイン項目の登録を解除します"
    open -n -a "$DEST" --args --unregister-login-item 2>/dev/null || true
    for _ in $(seq 1 15); do
        pgrep -f "$EXEC_PATH" >/dev/null 2>&1 || break
        sleep 0.2
    done
    pkill -f "$EXEC_PATH" 2>/dev/null || true
fi

if [ -d "$DEST" ]; then
    if rm -rf "$DEST" 2>/dev/null; then
        echo "削除しました: $DEST"
    else
        echo "${DEST} を削除できませんでした。権限を確認してください:" >&2
        echo "  sudo rm -rf \"$DEST\"" >&2
        exit 1
    fi
else
    echo "${DEST} は見つかりませんでした"
fi

if [ "$PURGE" = true ]; then
    defaults delete "$BUNDLE_ID" 2>/dev/null && echo "設定を削除しました" \
        || echo "削除する設定はありませんでした"
else
    echo "設定を残しています (消す場合は $0 --purge)"
fi
