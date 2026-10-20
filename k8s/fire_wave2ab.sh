#!/bin/bash
# Wave2-a/Wave2-bを開始する(1分おきの継続CronJob)。
# 使い方: ./fire_wave2ab.sh <team-context名> [a|b|both]
# 例: ./fire_wave2ab.sh team-a both
set -e

TEAM="$1"
WHICH="${2:-both}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$TEAM" ]; then
  echo "使い方: $0 <team-context名> [a|b|both]　例: $0 team-a both"
  exit 1
fi

echo "=== $TEAM: 05_wave2_attacks.yaml を適用(RBAC/SA込み) ==="
kubectl --context "$TEAM" apply -f "$SCRIPT_DIR/05_wave2_attacks.yaml"

if [ "$WHICH" = "a" ] || [ "$WHICH" = "both" ]; then
  echo "=== $TEAM: Wave2-a(socat)開始 ==="
  kubectl --context "$TEAM" delete cronjob wave2a-socat-loop -n gameday --ignore-not-found
  kubectl --context "$TEAM" apply -f "$SCRIPT_DIR/05_wave2_attacks.yaml"
fi
if [ "$WHICH" = "b" ] || [ "$WHICH" = "both" ]; then
  echo "=== $TEAM: Wave2-b(HTTP経由コマンドインジェクション)開始 ==="
  kubectl --context "$TEAM" delete cronjob wave2b-httpinjection-loop -n gameday --ignore-not-found
  kubectl --context "$TEAM" apply -f "$SCRIPT_DIR/05_wave2_attacks.yaml"
fi

echo ""
echo "1分おきに実行結果が記録されます。"
echo "直近の結果: kubectl --context $TEAM get jobs -n gameday -l gameday=wave2a --sort-by=.status.startTime"
echo "            kubectl --context $TEAM get jobs -n gameday -l gameday=wave2b --sort-by=.status.startTime"
echo "ログ:       kubectl --context $TEAM logs -n gameday -l gameday=wave2a --tail=20"
echo "            kubectl --context $TEAM logs -n gameday -l gameday=wave2b --tail=20"
echo "止める場合: kubectl --context $TEAM delete cronjob wave2a-socat-loop wave2b-httpinjection-loop -n gameday"
