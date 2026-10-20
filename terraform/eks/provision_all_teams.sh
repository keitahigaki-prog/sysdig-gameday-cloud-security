#!/bin/bash
# 各チームのEKSクラスタを一括で terraform apply する。
#
# 前提:
#   - 各チームのAWSプロファイル(例: gameday-team-a)が aws configure sso で設定済みであること
#   - teams.conf.example をコピーして teams.conf を作り、各チームのAWSアカウントID・
#     GameDayParticipantAccess許可セットのロール名を埋めてあること(teams.conf は.gitignore対象)
#
# 使い方: ./provision_all_teams.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$SCRIPT_DIR/teams.conf"

if [ ! -f "$CONF" ]; then
  echo "teams.conf が見つかりません。teams.conf.example をコピーして値を埋めてください。"
  exit 1
fi

while IFS='|' read -r TEAM ACCOUNT_ID ROLE_NAME; do
  [ -z "$TEAM" ] && continue
  case "$TEAM" in \#*) continue ;; esac

  DIR="$HOME/gameday-eks-$TEAM"
  echo "=== $TEAM ($ACCOUNT_ID): $DIR に展開 ==="
  mkdir -p "$DIR"
  cp "$SCRIPT_DIR/main.tf" "$DIR/main.tf"
  cat > "$DIR/terraform.tfvars" <<EOF
team_name              = "$TEAM"
account_id             = "$ACCOUNT_ID"
participant_role_name  = "$ROLE_NAME"
EOF
  (
    cd "$DIR"
    AWS_PROFILE="gameday-$TEAM" terraform init -input=false
    AWS_PROFILE="gameday-$TEAM" terraform apply -auto-approve
  )
  echo "=== $TEAM: 完了。kubeconfig登録コマンドをoutputsで確認してください ==="
done < "$CONF"

echo ""
echo "全チームのEKSクラスタapplyが完了しました。各チームで以下を実行してkubeconfigにcontextを登録してください:"
echo "  aws eks update-kubeconfig --region ap-southeast-2 --name gameday-<team> --alias <team> --profile gameday-<team>"
