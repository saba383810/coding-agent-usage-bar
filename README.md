# Coding Agent Usage Bar

Mac のメニューバーに Claude Code と Codex の使用量 (セッション 5h / 週制限 /
クレジット消費) を円ゲージ + % で常駐表示するアプリです


<img width="333" height="310" alt="スクリーンショット 2026-07-17 19 46 44" src="https://github.com/user-attachments/assets/338ce6bd-6f69-47d9-896f-c6fa5dc22d18" />


## 表示内容

- **メニューバー**: 円ゲージ + パーセント。色は使用率で変化
  (70% 未満: 緑 / 70–90%: オレンジ / 90% 以上: 赤)。
  どちらのゲージかは設定でアイコン (Claude: `asterisk` / Codex: `hexagon`) か
  文字 (`Cl` / `Cx`) を選べる
- **クリックでポップオーバー**:
  - Claude: Session (5h) / Week (all models) / Week (モデル別)
  - Codex: Credits (クレジット消費・請求段階・次の段階までのバー)。
    レート制限があるプランでは 5h / 週も
  - 各リミットのリセット時刻と残り時間
- **設定 (歯車ボタン)**: Claude / Codex それぞれの欄で
  - 使用量を表示するかどうか (外すと配下の項目も非アクティブになり、API も叩かない)
  - メニューバーに出すかどうかと、出す指標
  - Codex はクレジットの請求段階を出すかどうか
  - メニューバーの識別子をアイコンにするか文字にするか
- 3 分ごとに自動更新 (API が 429 を返した場合は間隔を倍々で広げ、最大 30 分)

Codex を使っていない環境 (`~/.codex/auth.json` が無い) では Codex の行と設定が
無効になるので、見た目は従来どおり Claude だけになる。

## データ源

どちらもトークンを外部に送ることはない (それぞれの API に Authorization ヘッダ
として渡すのみ)。トークンの期限が切れると 401 になるが、Claude Code / Codex を
使えば自動で更新されるので、ポップオーバーにその旨を表示するだけにしている。

### Claude

Claude Code が macOS Keychain (`Claude Code-credentials`) に保存している
OAuth トークンを使い、`https://api.anthropic.com/api/oauth/usage` を叩く。
`/usage` コマンドと同じデータ。

### Codex

Codex CLI が `~/.codex/auth.json` に保存している OAuth トークンを使い、
`https://chatgpt.com/backend-api/codex/usage` を叩く。`/status` と同じデータ。
ChatGPT backend は `User-Agent` が無いリクエストを 403 で弾くため、
リクエストには User-Agent を付けている。

#### 5h / 週制限の扱い

`rate_limit` (5h = primary / 週 = secondary) が返るのは Plus・Pro などの
レート制限プラン。ChatGPT Business / Enterprise シートでは null になり、
クレジット消費で管理されるため Credits だけが出る。

`additional_rate_limits` (モデル別・機能別の枠) は、使っていないモデルの枠が
0% で並ぶだけになるので **消費が 0 の枠は表示しない**。

#### クレジットの請求段階

`spend_control.individual_limit` から消費量・上限・残りを出し、請求段階と
**その段階の中でどこまで進んだか** をバーで添える。

| クレジット消費 | 請求 |
|---|---|
| 0 | なし |
| 上限の 1/20 まで | 40 ドル |
| 上限まで | 200 ドル |
| 上限超過 | 翌月まで利用不可 (上限緩和申請で継続可) |

素の段階は 1,000 / 20,000 クレジットだが、キャンペーンで上限が変わると境界も
同じ倍率で動くため、固定値ではなく API が返す `limit` に対する比率で判定して
いる (2026 年 7・8 月の 3 倍キャンペーン中は `limit` が 60,000 を返すので、
40 ドルの境界は 3,000 になる)。

上限に対する消費率は序盤ほとんど動かない (48.83 / 60,000 で 0.08%) ため、
段階内の進捗は別に出す。上の例なら 48.83 / 3,000 で 1.6% になり、
「次の段階まで 2,951」が見える。メニューバーの指標でもこの進捗を選べる。

`credits.balance` が返るクレジット残高制のプランでは、残高を別行で出す。

## ビルドと起動

Xcode 不要。Command Line Tools の Swift でビルドできる。

```sh
./build.sh
open build/CodingAgentUsageBar.app
```

## ログイン時に自動起動

1. `build/CodingAgentUsageBar.app` を `/Applications` にコピー
2. システム設定 → 一般 → ログイン項目 → 「+」で追加

## 構成

```
Package.swift                     SwiftPM 定義
Sources/CodingAgentUsageBar/
  App.swift                       MenuBarExtra 本体・メニューバーラベル
  ContentView.swift               ポップオーバー UI
  SettingsView.swift              設定 UI と設定ウィンドウ
  UsageSettings.swift             設定の永続化 (UserDefaults)
  UsageModel.swift                状態管理・ポーリング・メニューバー指標の選択
  UsageLimit.swift                共通モデル (UsageLimit / UsageError / パース補助)
  ClaudeUsageAPI.swift            Keychain 読み取り + Anthropic の usage API
  CodexUsageAPI.swift             ~/.codex/auth.json 読み取り + ChatGPT の usage API
  GaugeIcon.swift                 円ゲージ描画 (NSImage) と色
Info.plist                        LSUIElement=true (Dock 非表示)
build.sh                          ビルド + .app バンドル組み立て
```

## License

[MIT License](LICENSE)
