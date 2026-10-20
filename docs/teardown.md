# 撤去手順(開催後のクリーンアップ)

開催後、コストとセキュリティの両面から、作った環境は早めに壊す。手順は3段階(攻撃停止 → EKS/VPC破棄 → Sysdig接続解除)。チームごとに独立しているので、1チームずつ確認しながら進めても、全チーム一括で進めても良い。

## 0. 前提

- 各チームのAWSプロファイル(例: `gameday-team-a`)がローカルに設定済みであること。
- `terraform/eks/teams.conf`(`teams.conf.example`を元に作成した、実際のアカウントID入り・gitignore対象のファイル)が手元にあること。
- 以下はすべて実行者自身の端末・AWS/Kubernetes認証で行う。本リポジトリやClaude自身がAWS/kubectlに直接アクセスすることはない。

## 1. 攻撃CronJobの停止(最優先)

EKS/VPCを壊す前に、まず攻撃ループを止める。クラスタをそのまま残して調査を続けたい場合でも、ここだけは先にやっておくと安全。

```bash
for TEAM in team-a team-b team-c team-d team-e team-f; do
  echo "=== $TEAM ==="
  kubectl --context "$TEAM" -n gameday delete cronjob webshell-attack-loop wave2a-socat-loop wave2b-httpinjection-loop --ignore-not-found
done
```

`--ignore-not-found`により、すでに削除済み/クラスタが無いチームがあってもエラーで止まらない。

## 2. EKS/VPCの破棄

`terraform/eks/provision_all_teams.sh`でapplyしたディレクトリ(`~/gameday-eks-<team>/`)がそのまま残っているはずなので、そこで`destroy`する。

```bash
for TEAM in team-a team-b team-c team-d team-e team-f; do
  DIR="$HOME/gameday-eks-$TEAM"
  if [ -d "$DIR" ]; then
    echo "=== $TEAM: $DIR を destroy ==="
    (cd "$DIR" && AWS_PROFILE="gameday-$TEAM" terraform destroy -auto-approve)
  else
    echo "=== $TEAM: $DIR が無いのでスキップ ==="
  fi
done
```

一部のチームだけ既に手動で壊されている場合は、該当ディレクトリが無いか`terraform destroy`が「対象なし」で終わるだけなので安全。

## 3. Sysdig Cloud Account接続の解除

Sysdig側のCloud Account接続は、UI上の「切断」ボタンではなく、オンボーディング時に使ったTerraform(Sysdigの`sysdig_secure_cloud_auth_account`等を含むスタック)を`destroy`して外す。UIから切断すると、Terraform側のstateとAWS側のIAMロールが残ってしまい、再構築時に衝突する。

```bash
for TEAM in team-a team-b team-c team-d team-e team-f; do
  DIR="$HOME/sysdig-onboarding-gameday-$TEAM"
  if [ -d "$DIR" ]; then
    echo "=== $TEAM: $DIR を destroy ==="
    (cd "$DIR" && terraform destroy -auto-approve)
  else
    echo "=== $TEAM: オンボーディング用ディレクトリが見つかりません。手動で確認してください ==="
  fi
done
```

オンボーディング作業を参加者自身が行った場合、ディレクトリ名が規約通りになっていないことがある(例: 各自の好きな名前で作業している)。その場合はチームごとに実際のパスを確認してから実行する。

## 4. 実施後の確認

- SysdigのCloud Accounts一覧から、対象アカウントが消えている(または`disconnected`/エラー状態になっている)ことを確認する。
- AWSコンソール(またはCLI)で、対象アカウントにEKSクラスタ・VPC・関連IAMロールが残っていないことを確認する。
- 本番運用で使う可能性がある共有リソース(IAM Identity CenterのPermission Set本体など)は、個別チームのTerraform destroyでは消えないことがあるため、必要なら別途手動で整理する。

## 5. 対象外にした項目(次回検討)

- CIS/ポスチャー演習用に追加で作ったリソースの片付け(環境ごとに内容が異なるため、本リポジトリの範囲外)。
- 社内ドキュメント(Confluence等)側の更新。これは各社のドキュメント運用に合わせて別途行う。
