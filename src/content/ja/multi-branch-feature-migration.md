---
title: 複数拠点デプロイにおけるCherry-pickブランチ運用と機能同期戦略
excerpt: 同一コードベースを複数拠点に個別デプロイする現場において、環境汚染を防ぎ、トレーサビリティを担保する2段階Cherry-pickワークフローの実践。
---

同一のバックエンド・フロントエンドコードベースを複数の独立した工場・現場環境（オンプレミス/プライベートクラウド）へ展開する際、拠点ごとに固有のハードウェア通信設定、ライン構成、DBマイグレーションスクリプトが存在します。特定拠点で先行開発された共通機能を別拠点へ水平展開する場合、ブランチ同士を直接 `merge` することは、環境固有設定の混入（設定汚染）を引き起こす重大なアンチパターンとなります。

本稿では、主幹ブランチ（`prod_main`）を共通コミットの集約点とし、2段階の `cherry-pick` によって安全に機能を移植する運用規律を解説します。

## ブランチの役割分離

リポジトリ内のブランチは、その責務に応じて厳格に分類されます：

- **主幹ブランチ (`prod_main`)**: 全拠点共通の機能コミットを集約・標準化する基準線。特定の現場環境には依存しない。
- **拠点デプロイブランチ (`prod_factory_a`, `prod_factory_b` 等)**: 各工場の実稼働環境に対応し、拠点固有の設定やアダプターを保持する。
- **廃止された旧基準線 (`main`, `prod`)**: 履歴参照専用として凍結。

**基本原則**: 拠点デプロイブランチ同士を直接マージしてはならない。すべての機能移植は、`ソース拠点ブランチ` → `prod_main（単一コミットへ標準化）` → `ターゲット拠点ブランチ` の一方向経路のみを通過する。

```text
# アンチパターン（環境汚染の典型例）
git switch prod_factory_b
git merge origin/prod_factory_a  # 工場A固有のIPやスクリプトが混入する
```

![2段階Cherry-pickフロー：ソースブランチからprod_mainへの集約、prod_mainからターゲットブランチへの適用](/images/cherry-pick-flow.svg)

## 2段階 Cherry-pick ワークフロー

### 第1段階：ソースブランチから主幹ブランチへの集約と純化

ソース拠点における機能開発は、複数コミットに分散し、拠点固有のコードや未検証の周辺変更が混在していることが一般的です。主幹ブランチへ取り込む際は、コミット履歴をそのまま持ち込まず、変更を作業ツリーに展開して不要部分を除去します：

```bash
git fetch origin --prune
git switch prod_main
git pull --ff-only origin prod_main

# 関連コミットを作業ツリーに展開（即時コミットしない）
git cherry-pick -n <commit_1> <commit_2> <commit_3>
```

差分確認ツール（IDE等）を用いて以下の「純化」作業を行います：
- 共通機能モジュール（Service, Mapper, Entity, Controller）のみを残す；
- 拠点固有の接続設定、ハードコードされたIP、未承認のスレッドプール変更等をリセット；
- 共通 `pom.xml` の依存関係を最小限に整理；
- 単体テストを実行してビルドの整合性を確認。

検証後、単一の標準コミットとして記録します：

```bash
git commit -m "feat(common): add log platform module"
git push origin prod_main
```

### 第2段階：ターゲットブランチへの適用

主幹ブランチに標準化コミットが作成された後、ターゲットブランチ側で `-x` オプションを付与して適用します：

```bash
git switch prod_factory_b
git pull --ff-only origin prod_factory_b

# -x オプションで主幹コミットのSHAをコミットログに自動記録
git cherry-pick -x <commit_sha_from_prod_main>

# ターゲット環境でのモジュール単体テスト
mvn -pl log-platform -am clean test
git push origin prod_factory_b
```

`-x` 引数によってコミットメッセージ内に `(cherry picked from commit ...)` が自動追記され、コードの系譜（Lineage）が完全に追跡可能となります。拠点B固有の調整が必要な場合は、共通コミットを直接編集せず、独立した別コミットとして積み増します。

## 実践事例：ログ基盤モジュールの安全な移植

工場Aで開発されたログ基盤（3コミットに分散）を工場Bへ移植した実例：

| ソースコミット | コミット概要 | 分離対象（ノイズ） |
|---|---|---|
| `a1c9f0e` | ログ管理モジュールの新設 | 旧モジュールファイルの移動、ルートPOMの無関係な変更 |
| `b2d47a1` | コアService/Mapperの実装 | 工場A固有のPLC通信API、未完成のStarter |
| `c3e8b90` | エンティティ定義と設定クラス | 工場A専用のDB初期化SQL、フロントエンドのローカル変更 |

![ホワイトリスト抽出：共通モジュールと最小限のPOM変更のみを取り込み、環境固有コードを除外](/images/cherry-pick-selection.svg)

抽出ホワイトリスト：
- **適用対象**: `log-platform/**` 配下のJavaクラス、Controller、設定クラス、および関連モジュールの最小限のMaven依存宣言。
- **除外対象**: `log-platform-starter`（未承認）、工場A固有の機器ドライバ、DBマイグレーションSQL、Vueフロントエンドの局所修正。

実行コマンド列：

```bash
git switch prod_main
git pull --ff-only origin prod_main
git cherry-pick -n a1c9f0e b2d47a1 c3e8b90
git restore --staged .

# 不要ファイルの破棄とホワイトリストのステージング
git status --short
mvn -pl log-platform -am clean test
git add log-platform
git add -p pom.xml
git commit -m "feat(common): add log platform"
git push origin prod_main

# ターゲット側への適用
git switch prod_factory_b
git pull --ff-only origin prod_factory_b
git cherry-pick -x <prod_main_commit_sha>
mvn -pl log-platform -am clean test
git push origin prod_factory_b
```

## コンフリクト解決とロールバック手順

- **コンフリクト発生時**: 競合ファイルを解消後、`git add <file>` を実行し `git cherry-pick --continue`。取り消す場合は `git cherry-pick --abort` でクリーンな状態へ復帰。
- **ローカル作業の破棄**: `git reset --hard <origin_sha>` および `git clean -fd`。
- **リモートPush後のロールバック**: 履歴の強制書き換え（`push --force`）は行わず、`git revert <commit_sha>` を発行して打ち消しコミットを作成。

## コミット命名規則

コミットメッセージのプレフィックスを厳格に分類します：
- `feat(common):` 全拠点共通の標準機能追加
- `fix(common):` 全拠点共通の不具合修正
- `feat(factory-b):` 特定拠点固有の設定やアダプター追加

明確なブランチ運用規律と2段階Cherry-pickを徹底することで、複数拠点への個別デプロイにおける環境汚染を完全に排除し、長期的なコードベースの健全性を維持できます。
