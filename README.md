# Sysdig GameDay — Cloud Security 実践演習キット

AWS × Sysdig Secureを使った、チーム対抗型のクラウドセキュリティ演習(GameDay)一式。2026年にSysdigで実施したパイロット回(6チーム規模)の実際の構築物をベースに、他の人が同じ演習を再現できるよう整理したもの。

「オンボーディングしていないと攻撃が見えない」→「Sysdigを接続すると初めて侵害が見える」→「検知を見ながら初動対応する」という体験を、各チーム専用のAWSアカウント+EKSクラスタ上で再現する。

## これは何をする演習か

1. 各チームに、脆弱性を仕込んだWebアプリ(`vulnerable-webapp`)が動くEKSクラスタを用意する。
2. クラスタでは、開始直後から攻撃(認証情報窃取 → リバースシェル)がCronJobで自動的に繰り返し実行されている。
3. チームはまずSysdig Secureをオンボーディングして、何が起きているかを「見える」状態にする。
4. 検知ログから侵害範囲を調査し、ワークロードを止める・RBACや脆弱なコードを直すなどの初動対応を行う。
5. 対応後にSysdig側から再攻撃(Wave2)を仕掛け、本当に直っているかを検証する。
6. スコアボードで各チームの進捗(オンボーディング・検知・封じ込め・再攻撃ブロックなど)を自動/手動で記録し、リアルタイムで比較する。

詳細な設計意図は [`docs/architecture.md`](docs/architecture.md)、採点ルールは [`docs/scoring.md`](docs/scoring.md) を参照。

## 構成

```
terraform/eks/   EKSクラスタ+VPCを構築するTerraform(チームごとに1クラスタ)
k8s/             脆弱なWebアプリ・RBAC・攻撃CronJob(Wave1/Wave2)のマニフェスト
sysdig/          Sysdig Shield(Helm)の値ファイルの下書き
scoreboard/       自動/手動判定のライブスコアボード(単体のHTML)
docs/             設計・採点・撤去手順のドキュメント
```

## 前提条件

- チームの数だけ分離されたAWSアカウント(Organizationで一括管理、OUでまとめておくと楽)
- 各チームのAWSアカウントにSSO等でアクセスできるロール(IAM Identity CenterのPermission Set等)
- Sysdig Secureのテナント(チームごとにZoneを1つずつ作成して権限を分離)
- `terraform`, `kubectl`, `aws` CLI, `helm`

## セットアップ手順

### 1. チーム情報を設定する

```bash
cd terraform/eks
cp teams.conf.example teams.conf
# teams.conf を編集し、各チームの 実際のAWSアカウントID / IAM Identity Centerのロール名 を入れる
```

`teams.conf`は実際のアカウントIDを含むため`.gitignore`対象。コミットされるのは`teams.conf.example`(プレースホルダのみ)だけ。

### 2. 各チームのEKSクラスタを構築する

```bash
./provision_all_teams.sh
```

チームごとに`~/gameday-eks-<team>/`を作成し、`terraform apply`を実行する。完了後、出力されるコマンドで各チームのkubeconfigにcontextを登録する。

### 3. 脆弱なアプリと攻撃を展開する

```bash
kubectl --context <team> apply -f k8s/01_vulnerable-app.yaml
kubectl --context <team> apply -f k8s/02_rbac.yaml
kubectl --context <team> apply -f k8s/03_attacks_webshell.yaml
```

これで`webshell-attack-loop`が1分おきに自動実行され、認証情報窃取→リバースシェルの流れが継続的に発生する。

### 4. Sysdig Secureをオンボーディングする(チームの作業)

チームが自分でSysdig Secure(Shield)を各自のAWSアカウントに接続する。値ファイルの下書きは`sysdig/shield-values-template.yaml`を参照(**Helmチャートのキー名はバージョンに依存するため、適用前に`helm show values`で実際のキー名を確認すること**)。

### 5. スコアボードを開く

`scoreboard/index.html`をブラウザで開く(Sysdig MCPサーバーに接続できるCowork環境を想定。それ以外の環境で使う場合は`fetchAutoForTeam`内のMCP呼び出し部分を、使う環境のAPI呼び出しに置き換える)。

### 6. Wave2(再攻撃)で検証する

```bash
kubectl --context <team> apply -f k8s/05_wave2_attacks.yaml
# もしくは個別に即時発火
./k8s/fire_wave2.sh <team>
./k8s/fire_wave2ab.sh <team>
```

### 7. 終わったら撤去する

[`docs/teardown.md`](docs/teardown.md) の手順で、攻撃CronJob停止 → EKS/VPC破棄 → Sysdig Cloud Account接続解除、の順に片付ける。

## 重要な注意点

- `k8s/02_rbac.yaml`内のパスワード(`SuperSecretPilotPassword123`)は、演習用に仕込んだダミーの認証情報であり、実在のシステムでは使われていない。攻撃者に「窃取させる」ための教材データなので、そのまま公開して問題ない。
- 一方、`teams.conf`(実アカウントID)・kubeconfig・Sysdigのアクセスキーなど、実環境固有の値は`.gitignore`で除外している。自分の環境で使う際は、これらを別途自分で用意すること。
- コスト管理のため、演習が終わったら早めに撤去すること(EKSクラスタは放置すると課金が続く)。

## ライセンス

MIT License(必要に応じて変更して構わない)。
