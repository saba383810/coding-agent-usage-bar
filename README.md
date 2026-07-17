# Claude Usage Bar

Mac のメニューバーに Claude Code の使用量 (セッション 5h / 週制限) を
円ゲージ + % で常駐表示するアプリです


<img width="333" height="310" alt="スクリーンショット 2026-07-17 19 46 44" src="https://github.com/user-attachments/assets/338ce6bd-6f69-47d9-896f-c6fa5dc22d18" />


## 表示内容

- **メニューバー**: 円ゲージ + パーセント。色は使用率で変化
  (70% 未満: 緑 / 70–90%: オレンジ / 90% 以上: 赤)
- **クリックでポップオーバー**:
  - Session (5h) / Week (all models) / Week (モデル別) の各ゲージ
  - 各リミットのリセット時刻と残り時間
  - メニューバーに出す指標の切り替え (Session / Week 最大 / 全体の最大)
- 60 秒ごとに自動更新

## データ源

Claude Code が macOS Keychain (`Claude Code-credentials`) に保存している
OAuth トークンを使い、`https://api.anthropic.com/api/oauth/usage` を叩く。
`/usage` コマンドと同じデータ。トークンを外部に送ることはない
(Anthropic の API に Authorization ヘッダとして渡すのみ)。

トークンの期限が切れると 401 になるが、Claude Code を使えば自動で
更新されるので、ポップオーバーにその旨を表示するだけにしている。

## ビルドと起動

Xcode 不要。Command Line Tools の Swift でビルドできる。

```sh
./build.sh
open build/ClaudeUsageBar.app
```

## ログイン時に自動起動

1. `build/ClaudeUsageBar.app` を `/Applications` にコピー
2. システム設定 → 一般 → ログイン項目 → 「+」で追加

## 構成

```
Package.swift                     SwiftPM 定義
Sources/ClaudeUsageBar/
  App.swift                       MenuBarExtra 本体・メニューバーラベル
  ContentView.swift               ポップオーバー UI
  UsageModel.swift                状態管理・60 秒ポーリング
  UsageAPI.swift                  Keychain 読み取り + usage API
  GaugeIcon.swift                 円ゲージ描画 (NSImage) と色
Info.plist                        LSUIElement=true (Dock 非表示)
build.sh                          ビルド + .app バンドル組み立て
```

## License

MIT
