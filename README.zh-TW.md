# pickle

[English](README.md) · **繁體中文**

> 一個建構在 git 之上的 release 分支 commit 回補工具。

功能凍結時你切出一條 release 分支。接下來的一兩週，每個進到主線（trunk）的
hotfix 都得 cherry-pick 過去，而這件事常常被忘記、做了兩次，或順序做錯。
`pickle` 是一個自動完成這件事的 bash 腳本。

它基於 `git` 指令，所以同一道指令在 GitHub Actions、GitLab CI、Jenkins、Drone
或你自己的筆電上跑起來完全一樣，任何平台都能跑。

```
$ pickle sync --target release/1.2 --from main

pickle  main → release/1.2

  f79f8151  fix(DS-1234): null deref in parser        → picked
  df968438  feat(DS-1251): bulk export                → skip (type not selected)
  0cd7b34a  fix(DS-1240): retry on 502                → skip (already present, patch-id)
  10e2907a  fix(DS-1260): off-by-one in log rotation  → picked
  3b3bb192  fix!: drop legacy endpoint                → skip (breaking change; --allow-breaking to include)

  2 picked, 3 skipped
  pushed release/1.2 to origin
```

## 安裝

單一檔案，除了 bash 4+ 與 git 之外沒有任何相依套件。

在 **GitHub Actions** 上不需要安裝，action 本身帶著這支腳本，所以版本由你引用
的 tag 決定：

```yaml
- uses: riceball-tw/pickle@v1
  with:
    target: release/1.2
```

**其他環境**請釘在某個 release tag 上。不要讓 CI 指向 `main`：它會一直往前跑，
而這個工具會寫入你的 release 分支。

```bash
curl -fsSL https://raw.githubusercontent.com/riceball-tw/pickle/v1.0.0/pickle \
  -o /usr/local/bin/pickle
chmod +x /usr/local/bin/pickle
```

## 使用

```bash
pickle cut    --target release/1.2 --from main   # 功能凍結時執行一次
pickle sync   --target release/1.2 --from main   # 之後排程定期執行
pickle status --target release/1.2 --from main   # 只看 sync 會做什麼，不實際動手
```

`sync` 是冪等的，你想跑幾次都行。它也會把你放回原本所在的分支。

## 它如何決定要挑哪些 commit

預設會從標題行讀取 Conventional Commit 的 type，挑出 `fix` commit——這和 semver
判定 patch release 的規則相同。你可以追加 type，或直接用正規表達式取代這條規則：

```bash
pickle sync --target release/1.2 --types fix,perf
pickle sync --target release/1.2 --include '^\[HOTFIX\]' --exclude 'WIP'
```

如果你的規則根本無法用正規表達式表達，pickle 可以從 stdin 讀 commit，於是任何
你寫得出來的 `git log` 都能變成挑選規則：

```bash
git log --format=%H --grep=URGENT --author=oncall main \
  | pickle pick --target release/1.2 -
```

破壞性變更（`fix!:`，或帶有 `BREAKING CHANGE:` trailer）預設會被排除——它們是最
不該出現在 patch release 裡的東西；要納入請加 `--allow-breaking`。Merge commit
預設也會跳過，如果你用 squash-merge 這正是對的；如果你的主線是把 conventional
標題寫在 merge commit 上，`--first-parent` 會沿著主線的 first-parent 走，並以
`-m 1` 挑選 merge commit。

## 它如何避免重複挑同一個 commit

這部分必須做對，因為 `sync` 會對同一條分支跑上好幾百次。

1. **patch-id** 對 commit 的 *diff* 做雜湊，過程中會正規化空白與行號，並忽略
   SHA、訊息、作者與日期。就算有人手動 cherry-pick、改寫了訊息、作者也不同，
   雜湊值仍然和原本的 commit 一模一樣，所以 pickle 會跳過它。這不需要任何人遵守
   紀律，而且涵蓋了幾乎所有情況。

2. **`-x` trailer** 補上 patch-id 唯一漏掉的情況：有人*解決了衝突*，因此實際落
   地的 diff 和原本不同。`git cherry-pick -x` 會在訊息裡記下
   `(cherry picked from commit …)`，`--continue` 會讓這行在解衝突之後保留下來，
   而 pickle 會掃描 release 分支上的這些 trailer。你不需要記住這件事——當某次挑
   選發生衝突時，pickle 會把該執行的指令原封不動印出來，`-x` 也包含在內。

3. **`pickle skip`** 涵蓋前兩個訊號都看不到的情況：你決定不出的修正，或是直接在
   release 分支上修掉的 bug。它會寫下一個空 commit，帶著偵測器本來就會讀的那個
   trailer——不需要新機制，也在歷史裡留下一行可稽核的紀錄，說明這是人為的決定。

```bash
pickle skip --target release/1.2 abc1234 --reason "depends on a feature not in 1.2"
```

## 發生衝突時

pickle 依照主線上的順序挑選，並且**在第一個衝突處停下來**。先前已經挑好的
commit 會保留並 push；發生衝突的那一個會被 abort，因此不會有任何衝突標記進到
remote；整趟執行會以非零狀態結束，讓 build 變紅。

停下來是為了保住順序。如果 fix #4 其實依賴 fix #2，跳過 #2 卻讓 #4 落地，你會得
到一條編譯得過、但內容是錯的 release 分支。`--keep-going` 讓你在 hotfix 之間確實
互相獨立時選擇另一種取捨——它會把所有能套用的都套上去，但結束狀態仍然是非零。

```
  ✗ conflict picking 0cd7b34a  fix(DS-1240): retry on 502
      http.c

  the branch was left clean; nothing half-applied was pushed.

  resolve it locally:
    git fetch origin
    git switch release/1.2
    git cherry-pick -x 0cd7b34a
    # fix the conflict, then:
    git add -A && git cherry-pick --continue
    git push origin release/1.2
```

## 指令

| | |
|---|---|
| `pickle cut` | 從主線建立 release 分支並 push。每個 release 執行一次。 |
| `pickle sync` | 把所有符合條件、且尚未存在的 commit 挑過去，然後 push。主力指令。 |
| `pickle status` | 顯示 `sync` 會做什麼。不會改動任何東西，連分支都不會切換。 |
| `pickle pick` | 挑選指定的 commit，忽略標題過濾條件。`-` 表示從 stdin 讀 SHA。 |
| `pickle skip` | 記錄某個 commit 是刻意不回補的。 |

## 參數

| 參數 | 預設 | |
|---|---|---|
| `--target BRANCH` | — | 要挑進去的 release 分支。必填。就是字面上的分支名稱；pickle 不假設任何命名慣例。 |
| `--from BRANCH` | `origin/HEAD`，否則 `main`/`master` | 要從哪條主線挑。 |
| `--remote NAME` | `origin` | |
| `--types LIST` | `fix` | 要挑的 Conventional Commit type，以逗號分隔。 |
| `--include REGEX` | — | 改用這個 ERE 比對標題，取代 `--types`。 |
| `--exclude REGEX` | — | 排除標題符合此 ERE 的 commit，在 include 之後套用。 |
| `--first-parent` | 關閉 | 沿著主線的 first-parent 走，並以 `-m 1` 挑選 merge commit。 |
| `--allow-breaking` | 關閉 | 連破壞性變更也一起挑。 |
| `--keep-going` | 關閉 | 遇到衝突時跳過該 commit 並繼續。 |
| `--dry-run` | 關閉 | 只回報，不做任何改動。 |
| `--no-push` | 關閉 | 在本機落地 commit，但不 push。 |
| `--no-fetch` | 關閉 | 直接使用本機既有的 ref。 |

每個參數也都可以透過 `PICKLE_` 開頭的環境變數設定（`PICKLE_TARGET`、
`PICKLE_FROM`、`PICKLE_TYPES`、`PICKLE_INCLUDE`、`PICKLE_EXCLUDE`、
`PICKLE_REMOTE`），因為在 CI matrix 裡設環境變數比組 argv 容易得多。參數優先於
環境變數。

## 結束碼

| | |
|---|---|
| `0` | 所有選中的 commit 都已落地，或本來就沒事可做。 |
| `1` | 有 commit 發生衝突，需要人來處理。 |
| `2` | 用法錯誤。 |
| `3` | 儲存庫或環境不在 pickle 能運作的狀態。 |

紅色的 build 就是通知本身。pickle 不會開 issue、也不會在 PR 上留言，因為那意味
著要用代管平台的 API，而那正是它刻意不碰的東西。

## CI

完整範例在 [`examples/`](examples/)。

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0          # 必要：cherry-pick 需要完整歷史

- uses: riceball-tw/pickle@v1
  with:
    target: release/1.2
    from: main
```

| input | 預設 | |
|---|---|---|
| `command` | `sync` | `sync`、`status`、`cut` 或 `skip` |
| `target` | — | Release 分支。必填。 |
| `from` | 儲存庫的預設分支 | 主線分支。 |
| `types`、`include`、`exclude` | | 挑選條件，同上方參數表。 |
| `args` | — | 其他任何參數，原樣傳入：`--keep-going --allow-breaking` |

這個 job 需要 `permissions: contents: write` 才能 push。

在其他環境有兩件事要注意。**完整歷史**：`actions/checkout` 預設是
`fetch-depth: 1`，這會讓 cherry-pick 無法進行——pickle 偵測到淺層 clone 時會自己
加深而不是直接失敗，但還是把 `fetch-depth: 0` 設好，免得每次執行都付這個成本。
**push 權限**：pickle 依設計會直接 push 到 release 分支，所以受保護的
`release/*` 需要為 CI 身分開例外，或者把 pickle 放到有權限 push 的地方跑。

不需要設定 `user.email`。CI checkout 通常沒有這個設定，而這正常會讓
`cherry-pick` 拒絕執行；pickle 會以 `pickle <noreply@pickle.invalid>` 作為
*committer*，並保留原本的作者不動，所以 `git log` 仍然會記上真正寫這個修正的人。

## Agent skill

`skills/pickle/` 會教 AI coding agent 怎麼操作這個工具：有哪些指令、結束碼的意
義、先跑 `--dry-run` 的習慣，以及如何在解衝突時不把 `-x` trailer 弄丟。

```bash
npx skills add riceball-tw/pickle           # 任何 agent：Claude Code、Cursor…

/plugin marketplace add riceball-tw/pickle  # Claude Code，以 plugin 形式安裝
/plugin install pickle@pickle

cp -r skills/pickle ~/.claude/skills/       # 或者直接複製過去
```

## 它刻意不做的事

打 tag 與發布。建立 PR 或 MR。產生 changelog。任何需要代管平台 API 的事。把
hotfix 從 release 分支反向移植回主線。

pickle 假設你在功能凍結時從主線切出 release 分支，然後往前回補。它不是為了長期
維護的 LTS 分支而設計——那種把 release 疊在一個老很多的基底上組出來的做法雖然也
能跑，但你會把人生都花在解衝突上，而這個工具幫不了你。

## 測試

```bash
./test/run.sh          # 全部
./test/run.sh conflict # 名稱含有該字串的案例
KEEP=1 ./test/run.sh   # 保留 fixture 儲存庫以便檢查
```

測試會在暫存目錄裡建出真正的 git 儲存庫，並用真正的腳本去跑。沒有任何東西被
mock，因為 pickle 面對真實 git 時的行為，就是這個產品的全部。

---

英文版 [README.md](README.md) 為主要版本；兩者不一致時以英文版為準。
