# Sysdig GameDay — Cloud Security 実践演習キット

AWS × Sysdig Secureを使った、チーム対抗型のクラウドセキュリティ演習(GameDay)一式。2026年にSysdigで実施したパイロット回(6チーム規模)の実際の構築物をベースに、他の人が同じ演習を再現できるよう整理したもの。

想定読者は、この演習を自分の組織で運営する側(AWS Organizations・IAM Identity Center・Sysdig Secureテナントに対する管理者権限を持つ人)。参加チーム側は、運営から渡されたログイン情報でSysdig Secureをオンボーディングし、検知・初動対応を行うだけで良い。

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

運営側が事前に準備しておく必要があるもの。特に最初の2つはTerraformやスクリプトの範囲外(AWSコンソール/IAM Identity Center UIでの手作業)なので、他のメンバーに引き継ぐ際は見落とされやすい。

- **チームの数だけ分離されたAWSアカウント**(Organizationで一括管理、GameDay用のOUを1つ作ってその下にぶら下げると楽)
- **IAM Identity Centerで、チームごとに「ログイン可能なUser」と「Permission Set(例: `GameDayParticipantAccess`)」を作成し、各チームのアカウントにAccount Assignmentまで済ませておく**
  - OUとPermission Setを定義しただけでは入れない。実際にUserを作成し、本人に招待メール(またはログイン情報)を届けるところまでが必須([`docs/architecture.md`](docs/architecture.md)の「教訓」参照)
- **運営の手元の端末で、チームごとのAWS CLIプロファイルを設定しておく**(`aws configure sso` 等で、プロファイル名は `gameday-team-a` のようにチーム名を含める。Terraform/シェルスクリプト側がこの命名を前提にしている)
- **Sysdig Secureのテナントで、チームごとにZoneを1つずつ作成しておく**(Sysdig Secure UIの Settings > Zones。各ZoneをそのチームのEKSクラスタにスコープすることで、チームは自分の検知・スコアだけが見える状態になる)
- `terraform`, `kubectl`, `aws` CLI, `helm`

## セットアップ手順

### 1. チーム情報を設定する

```bash
cd terraform/eks
cp teams.conf.example teams.conf
# teams.conf を編集し、各チームの 実際のAWSアカウントID / IAM Identity Centerのロール名 を入れる
```

`teams.conf`は実際のアカウントIDを含むため`.gitignore`対象。コミットされるのは`teams.conf.example`(プレースホルダのみ)だけ。ロール名の確認方法は`teams.conf.example`内のコメントを参照。

### 2. 各チームのEKSクラスタを構築する

```bash
./provision_all_teams.sh
```

チームごとに`~/gameday-eks-<team>/`を作成し、`terraform apply`を実行する。完了後、出力されるコマンドで各チームのkubeconfigにcontextを登録する。

リージョンは`terraform/eks/main.tf`の`region`変数で既定`ap-southeast-2`(Sydney)。別リージョンで実施する場合は、`provision_all_teams.sh`が生成する`terraform.tfvars`に`region = "..."`を追記するか、`main.tf`側の`default`を書き換える。

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

`scoreboard/index.html`をブラウザで開く。

**注意**: 自動判定部分(オンボーディング・検知・初動対応・Wave2-aブロック)は、Sysdig Secure MCPサーバーに接続できるCowork環境で開くことを前提にしている。それ以外の環境(素のブラウザ単体など)で使う場合、自動判定は動かないため、`fetchAutoForTeam`内のMCP呼び出し部分を、Sysdig REST APIなど使う環境のAPI呼び出しに書き換える必要がある。手動判定分(Wave2-b・インシデントレポート提出など、[`docs/scoring.md`](docs/scoring.md)参照)はMCPに依存せずブラウザのlocalStorageだけで動く。

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
