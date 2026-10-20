#!/bin/bash
# Wave2: 継続攻撃ループ(webshell-attack-loop CronJob)は1分おきに自動実行されているが、
# 次のスケジュールを待たずに「今すぐ1回」結果を見たいときに使う(on-demand trigger)。
# 使い方: ./fire_wave2.sh team-c
set -e

TEAM="$1"
RUN_NAME="manual-trigger-$(date +%s)"

if [ -z "$TEAM" ]; then
  echo "使い方: $0 <team-context名>　例: $0 team-c"
  exit 1
fi

echo "=== $TEAM: CronJobから即時1回実行 ==="
kubectl --context "$TEAM" create job "$RUN_NAME" --from=cronjob/webshell-attack-loop -n gameday

echo "結果を待っています..."
kubectl --context "$TEAM" wait --for=condition=complete --for=condition=failed "job/$RUN_NAME" -n gameday --timeout=30s || true

echo ""
echo "----- $TEAM の結果 ($RUN_NAME) -----"
kubectl --context "$TEAM" logs -n gameday "job/$RUN_NAME"
echo "-------------------------"
echo "BLOCKED が出ていれば防御成功(Wave2ボーナス+15点)、SUCCEEDED が出ていれば防御失敗です。"
echo "継続ループ自体の直近の実行結果は: kubectl --context $TEAM get jobs -n gameday -l gameday=attack --sort-by=.status.startTime"
