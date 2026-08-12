# YUI OS Makefile 設計書（Step 8-B ビルドシステム改善）

| 項目 | 内容 |
|---|---|
| 文書名 | ~~yuios_makefile_design_v0_1.md~~ → **yuios_makefile_design_v0_2.md** |
| バージョン | ~~v0.1（レビュー前ドラフト・案）~~ → **v0.2（レビュー指摘反映・再レビュー待ち）** |
| 作成日 | 2026-06-21 |
| 作成者 | Claude (Anthropic) |
| 対象工程 | Step 8-B（ビルドシステム改善・手順書 §10 残課題 No.1/4/5） |
| Status | **DRAFT（再レビュー承認前。原則43によりレビュー完了まで実装着手しない）** |
| 上位文書 | yuios_build_procedure v1.6（§4.11 道2ビルド・§10 将来課題）／HANDOVER_CHAT62.md／review_yuios_makefile_design_v0_1.docx v1.0 |
| 確定方針 | 2026-06-21 ユーザー決定：①Force本体改修=見送り ②最小Makefile ③Dhrystoneも対象 |

### 改版履歴

| 版 | 日付 | 内容 |
|---|---|---|
| v0.1 | 2026-06-21 | 初版ドラフト |
| **v0.2** | 2026-06-21 | レビュー指摘書 v1.0 を反映。**M-A**（`.ONESHELL:`/`SHELL`/`.SHELLFLAGS` 明記）・**M-B**（`$`エスケープ確定＋`make -n`必須化）・**M-C**（mk_post1.sh 依存追加・ツール更新時 clean 注記）・**E-A**（REF_BIN 循環参照解消＝凍結退避品）・**E-B**（clean ワイルドカード KY）を反映。C-1/C-2/C-3/D-1/E-1 のレビュア回答を取り込み |

---

## 0. 本設計のスコープ（確定方針に基づく境界）

### 0.1 やること（対象）

| No. | 課題 | 本設計での解決 |
|---|---|---|
| **4** | lds 手書き／ビルドスクリプト乱立 | 単一 `Makefile` に `yuios`（道2）と `dhrystone` の2ターゲットを並置。Dhrystone の lds は Makefile 規則で自動生成 |
| **5** | ディスクイメージ手動 | `make disk` ターゲットで既定ファイル名 `disk.img` を生成。`make run` が `disk.img` を自動使用 |
| **1** | Force 混入行 `#WORD_xxx` | 混入行除去（後処理1）を Makefile の明示ルールに格上げ。**Force本体は改変しない**（sed後処理を build_road2.sh と等価のまま規則化） |

### 0.2 やらないこと（対象外・最小維持のため）

- **Force 本体（codegen）の改修**（混入行を出さないようにする根本対処）= 今回見送り（確定方針）。
- **ツール群（force/hasm23/lnk23/emu23）のコンパイル**は Makefile 対象外。既ビルド済みバイナリが
  カレントにある前提。Makefile は OS/Dhrystone の **成果物 .bin 生成**に限定。
- FileMgr 各テストビルド（`build_v0_10_*.sh` 系）の統合 = 対象外（将来課題に残置）。
- mkfs_yuifs.py 本体の改修 = 不要（既定名運用は Makefile 側で吸収）。

### 0.3 絶対ゲート（合否判定の必須条件）

| 対象 | 判定基準 | 根拠 |
|---|---|---|
| yuios（道2） | `yuios.bin` が従来 .bin リンク版と **全56416バイト完全一致**（`cmp`） | 道2 I3 実績 |
| dhrystone | `826 / 48405 / P:20` 完全一致 | 必須回帰試験値 |

**Makefile は build_road2.sh / 既知 Dhrystone 手順と「ビルド内容が等価」であることが設計目標。**
記述形式を shell→Makefile に変えるだけで、ツールへの入力バイト列・順序・オプションは一切変えない。
これにより 56416 一致・826 一致は構造的に保たれる（本日KYのリスク低減策）。

---

## 1. 現状のビルド経路（実ファイル根拠・憶測なし）

### 1.1 yuios 道2（build_road2.sh 準拠・全7ステップ）

```
S1 Force        : ./force --target ysd8800_kern --tgt-file ysd8800_kern.tgt \
                          --prim-file ysd8800.prim <forth.fs> -o kf_r2.asm
S2 後処理1(No.1): #WORD_xxx を全自動抽出 → 1パス目アドレスで #$addr に直書き
                  （sed -E 's/#WORD_[A-Z0-9_]+/#$0000/g' で一時asm→hasm23→.sym取得→本置換）
S3 後処理2      : WORD_OS_START 定義直前に .global を awk 挿入
S4 hasm23 -c    : kf_r2.asm → kf_r2.asm.obj（YOF・load_addr=$5100・has_org）
S5 kernel置換   : sed 's|#$e96e|#$WORD_OS_START|g' kernel_v12_7.asm > kf_r2_kern.asm
S6 hasm23 -c    : kf_r2_kern.asm → kf_r2_kern.asm.obj（YOF・load_addr=$0000・UNDEF reloc=2）
S7 lnk23        : ./lnk23 -o yuios.bin --sym yuios.sym --machine force \
                          kf_r2.asm.obj kf_r2_kern.asm.obj   ★--machine force 必須（L-E）
```

### 1.2 dhrystone（道2版・L-B 準拠・全8ステップ）

```
D1 scc23  : ./scc23 --code-org 0x0400 --data-org 0x4000 --runtime-org 0x0100 \
                    -o dhry.asm dhry_timer.c   ★3オプション必須（L-B・落とすとUnknown opcode 33）
D2 hasm23 : ./hasm23 dhry.asm                  （_main アドレス取得のため）
D3 抽出   : MAIN=$(grep -E '^[0-9a-f]+ _main$' dhry.asm.sym | awk '{print $1}')  # 期待 04cc
D4 sed    : JSR _main を JSR $<MAIN> に直書き（startup_harness23_v15.asm → startup_harness23.asm）
            ※ No.2 の残置（Dhrystone harness は当面 sed 併用可・手順書§10注記）
D5 hasm23 : ./hasm23 startup_harness23.asm
D6 lds生成: cat > dhry.lds <<EOF
              SECTION code 0x0000 dhry.asm.bin
              SECTION harness 0x0000 startup_harness23.asm.bin
            EOF
D7 lnk23  : ./lnk23 -o dhry_final.bin --sym dhry_final.sym dhry.lds  （machine既定=baremetal）
D8 実行   : timeout 30 ./emu23 dhry_final.bin -q   # 期待 826/48405/P:20
```

### 1.3 disk（No.5・mkfs_yuifs v1.1）

```
DK mkfs : python3 mkfs_yuifs.py disk.img --size-kb 32 --add-file hello.txt
          （既定名 disk.img。テスト毎に作り直し必須＝汚染回避・手順書§6.10）
```

---

## 2. Makefile 設計

### 2.1 ターゲット一覧

| ターゲット | 動作 | 生成物 |
|---|---|---|
| `all`（既定） | = `yuios` | yuios.bin / yuios.sym |
| `yuios` | 道2ビルド（S1〜S7） | yuios.bin / yuios.sym |
| `dhrystone` | Dhrystone ビルド（D1〜D7） | dhry_final.bin / dhry_final.sym |
| `disk` | ディスクイメージ生成（DK） | disk.img |
| `run` | `yuios` + `disk` 後に emu23 起動 | （実行のみ） |
| `regress` | `dhrystone` 後に emu23 で 826/48405/P:20 を判定 | （判定のみ） |
| `verify` | `yuios` 後に基準 .bin と `cmp`（56416一致判定） | （判定のみ） |
| `clean` | 中間・成果物の削除 | — |

### 2.2 Makefile 必須プリアンブル（★v0.2 新設・M-A 致命的指摘の反映）

**最重要。** GNU Make はレシピの各行を独立サブシェルで実行する。build_road2.sh / Dhrystone 手順は
シェル変数（例 D4 の `MAIN`）を行をまたいで受け渡すため、これを行継続なしに移植すると変数が
**空展開し、設計は正しいのにビルドが通らない L-A 事象**になる。これを防ぐため Makefile 冒頭に
以下を必須で記述する。

```make
SHELL       := /bin/bash
.SHELLFLAGS := -ec        # -e: 途中失敗で即停止（見えているバグを残さない）／-c: コマンド実行
.ONESHELL:                # 各ターゲットのレシピ全体を単一シェルで実行
                          # → build_road2.sh と同一のシェル変数スコープを再現
```

| 効果 | 根拠 |
|---|---|
| `.ONESHELL:` によりレシピ全体が1シェル＝`MAIN` 等が行をまたいで保持 | レビュー M-A／D-3 |
| `-e` により S2〜S7 / D1〜D7 の途中失敗で即停止 | 原則「見えているバグを先に潰す」 |
| build_road2.sh のシェル変数受け渡しを変形なしに移植可能 | J-2（バイト等価）の前提条件 |

> **`.ONESHELL:` 使用時の注意**：レシピ全体が1シェルになるため、途中の `cd` が後続行に波及する。
> 本設計はカレント固定で `cd` を使わないため影響なし。また `.SHELLFLAGS := -ec` の `-e` により、
> レシピ途中のコマンド失敗が（行継続でなくても）ターゲット失敗として正しく伝播する。

### 2.3 変数定義（ツールパス・ファイル名の一元管理）

```make
# ---- ツール（既ビルド済み前提・カレント配置） ----
FORCE   := ./force
HASM    := ./hasm23
LNK     := ./lnk23
SCC     := ./scc23
EMU     := ./emu23
MKFS    := python3 mkfs_yuifs.py

# ---- 入力ソース（本番・非改変） ----
FORTH_SRC := kernel_forth_v0_10_18.fs
KERN_SRC  := kernel_v12_7.asm
TGT       := ysd8800_kern.tgt
PRIM      := ysd8800.prim
DHRY_SRC  := dhry_timer.c
HARNESS   := startup_harness23_v15.asm

# ---- 中間（実験ファイル名・KY28/38 本番非改変） ----
FORTH_ASM := kf_r2.asm
KERN_ASM  := kf_r2_kern.asm
FORTH_OBJ := kf_r2.asm.obj
KERN_OBJ  := kf_r2_kern.asm.obj

# ---- 成果物 ----
YUIOS_BIN := yuios.bin
YUIOS_SYM := yuios.sym
DHRY_BIN  := dhry_final.bin
DISK      := disk.img
DISK_KB   := 32
DISK_FILE := hello.txt

# ---- 検証（★v0.2 E-A 反映：循環参照回避） ----
REF_BIN   := yuios_ref_road2_I3.bin   # 道2 I3 統合試験 PASS で確定した既知良品を
                                       # バージョン刻印付きで凍結退避したもの。
                                       # ★yuios.bin 自身を基準にしない（自己比較は検証無効）。
                                       # 56416 バイトの出所＝道2 I3「全56416バイト完全一致」実績。
```

### 2.4 yuios ターゲット規則（S1〜S7）

build_road2.sh の各ステップを 1:1 で Makefile レシピ化する。**コマンド内容は build_road2.sh と
バイト等価**（オプション・順序・sed パターンを一切変えない）。

```make
$(YUIOS_BIN): $(FORTH_SRC) $(KERN_SRC) $(TGT) $(PRIM) mk_post1.sh
	# S1 Force
	$(FORCE) --target ysd8800_kern --tgt-file $(TGT) --prim-file $(PRIM) $(FORTH_SRC) -o $(FORTH_ASM)
	# S2 後処理1（混入行 #WORD_xxx 全自動抽出・No.1） … build_road2.sh Step2 と同一スクリプトを
	#    Makefile から呼ぶ（複雑なため別シェル断片 mk_post1.sh に切り出し＝可読性・KY）
	./mk_post1.sh $(FORTH_ASM) $(HASM)
	# S3 後処理2（.global 挿入）
	awk '/^WORD_OS_START:/ && !d { print ".global WORD_OS_START"; d=1 } { print }' \
	    $(FORTH_ASM) > $(FORTH_ASM).g && mv $(FORTH_ASM).g $(FORTH_ASM)
	# S4 hasm23 -c（forth.obj）
	$(HASM) -c $(FORTH_ASM)
	# S5 kernel UNDEF 化（No.6 は道2で解決済・ここは sed 1行のまま）
	sed 's|#\$$e96e|#\$$WORD_OS_START|g' $(KERN_SRC) > $(KERN_ASM)
	# S6 hasm23 -c（kernel.obj）
	$(HASM) -c $(KERN_ASM)
	# S7 lnk23（★--machine force 必須）
	$(LNK) -o $(YUIOS_BIN) --sym $(YUIOS_SYM) --machine force $(FORTH_OBJ) $(KERN_OBJ)

yuios: $(YUIOS_BIN)
```

> 注：Make では `$` を `$$` でエスケープする必要があるため、sed の `#$e96e` は `#\$$e96e` と書く。
> これは記述上の差であり、シェルに渡る最終文字列は build_road2.sh と同一（要・実ビルドで cmp 確認）。

### 2.5 dhrystone ターゲット規則（D1〜D8）

```make
$(DHRY_BIN): $(DHRY_SRC) $(HARNESS)
	# D1 scc23（★3オプション必須・L-B）
	$(SCC) --code-org 0x0400 --data-org 0x4000 --runtime-org 0x0100 -o dhry.asm $(DHRY_SRC)
	# D2-D3 _main 取得
	$(HASM) dhry.asm
	# D4 JSR _main 直書き（No.2 残置）★v0.2: .ONESHELL 前提で行継続「\」不要・エスケープ確定
	#   Make は $$ を $ に1回畳んでシェルへ渡す。.ONESHELL によりレシピ全体が単一 bash のため
	#   MAIN はこの後の行でも保持される（D-3）。シェル側で MAIN=... と ${MAIN} 参照が成立。
	MAIN=$$(grep -E '^[0-9a-f]+ _main$$' dhry.asm.sym | awk '{print $$1}')
	sed -E "s/JSR[[:space:]]+_main/JSR  \$$$${MAIN}/" $(HARNESS) > startup_harness23.asm
	#   ↑ シェルが受け取る最終文字列: sed -E "s/JSR[[:space:]]+_main/JSR  \$${MAIN}/"
	#     sed 置換先の \$ はリテラル '$'、${MAIN} はシェル変数展開（例 04cc）→ "JSR  $04cc"
	#   ★D-2（make -n で最終文字列を目視）で build_road2 既知手順と一致することを必須確認
	# D5 hasm23
	$(HASM) startup_harness23.asm
	# D6 lds 自動生成（No.4 の核心：手書き lds 廃止）
	printf 'SECTION code 0x0000 dhry.asm.bin\nSECTION harness 0x0000 startup_harness23.asm.bin\n' > dhry.lds
	# D7 lnk23
	$(LNK) -o $(DHRY_BIN) --sym dhry_final.sym dhry.lds

dhrystone: $(DHRY_BIN)
```

### 2.6 disk / run / regress / verify / clean

```make
disk:
	$(MKFS) $(DISK) --size-kb $(DISK_KB) --add-file $(DISK_FILE)

run: yuios disk
	timeout 30 $(EMU) $(YUIOS_BIN) -q --disk $(DISK)

regress: dhrystone
	@timeout 30 $(EMU) $(DHRY_BIN) -q 2>&1 | grep -iE 'Dhrystones/sec|cycles|P:'
	@echo '期待値: Dhrystones/sec=826 / cycles=48405 / P:20'

verify: yuios
	@if cmp -s $(YUIOS_BIN) $(REF_BIN); then \
	   echo 'VERIFY OK: yuios.bin は基準と全56416バイト一致'; \
	 else echo 'VERIFY FAIL: 基準と差分あり（要調査）'; exit 1; fi

clean:
	rm -f $(FORTH_ASM)* $(KERN_ASM)* $(FORTH_OBJ) $(KERN_OBJ) \
	      dhry.asm* startup_harness23.asm* dhry.lds \
	      $(YUIOS_BIN) $(YUIOS_SYM) $(DHRY_BIN) dhry_final.sym
	# 注：disk.img は誤消去防止のため clean 対象外（明示 rm を推奨）
```

### 2.7 補助スクリプト mk_post1.sh（S2 混入行除去）

S2 の混入行除去は1パス目アセンブル→.sym取得→全自動置換と多段で、Makefile レシピに直書きすると
可読性を損なうため、build_road2.sh の Step2 と**同一ロジック**を `mk_post1.sh` に切り出す。
中身は build_road2.sh からの移植（新規ロジックなし）。引数：`$1`=forth asm、`$2`=hasm パス。

> **★v0.2（M-2 レビュア条件）**：mk_post1.sh の中身は build_road2.sh Step2 からの**バイト等価移植に限定**し、
> 新規ロジックを混入させない（混入すると 56416 一致が崩れる）。また M-C のとおり mk_post1.sh は
> `$(YUIOS_BIN)` の前提条件に追加済み（§2.4）＝スクリプト更新時に yuios.bin が再生成される。

---

## 3. 設計上の判断と根拠

| 判断 | 内容 | 根拠 |
|---|---|---|
| J-1 | Force/ツールのコンパイルは Makefile 対象外 | 最小維持（確定方針）。L-F のディレクトリ構成依存を持ち込まない |
| J-2 | コマンド内容は既存スクリプトとバイト等価 | 56416/826 を構造的に保つ（KY本日）。記述形式変更のみ |
| J-3 | S2 を別シェル断片に分離 | Make の `$` エスケープ地獄を避け可読性確保。ロジック新規追加なし |
| J-4 | `disk.img` を clean 対象外 | 作り直しは `make disk` で明示。誤消去・汚染（§6.10）の両睨み |
| J-5 | `verify`/`regress` を独立ターゲット化 | 絶対ゲート（§0.3）を「叩けば判定」できる形にし回帰の取りこぼし防止（L-B 再発防止） |
| J-6 | No.2（JSR _main sed）は Dhrystone で残置 | 手順書§10 注記どおり。今回スコープ外。lnk23クロス参照対応は別途 |
| **J-7**（v0.2・M-C） | **ツール（force/hasm23/lnk23/emu23）差し替え時は `make clean` を必須とする** | ツールバイナリは Makefile 依存に含めない（J-1）帰結。Make はツール更新を検知できないため、古い中間生成物が残ると 56416 不一致・誤回帰の温床。本プロジェクト「ツールは常に最新版を確認」原則の取りこぼし防止 |

---

## 4. テスト計画（実装承認後に実施）

### 4.1 前段ゲート（★v0.2 追加・レビュー D 項目・MK 群より先に実施）

| ID | 内容 | 合否基準 |
|---|---|---|
| **D-2** | `make -n yuios` / `make -n dhrystone` でシェル展開後の最終コマンド文字列を目視確認 | build_road2.sh / 既知 Dhrystone 手順と文字列一致 |
| **D-3** | `.ONESHELL:` 適用後、yuios/dhrystone レシピ内のシェル変数が行をまたいで保持される | `MAIN` 等が空展開しない |
| **D-4** | ツール差し替え→`make clean`→再 `make` で 56416 一致が再現（J-7 実証） | cmp 一致 |

**D-2 が最重要前段ゲート**：M-A/M-B の `$` エスケープ・シェル変数問題は、実ビルド前に
`make -n`（dry-run）でシェルに渡る最終文字列を確認すれば机上で検出できる。L-A（机上OK・
実ビルドNG）を最小コストで潰す関所。

### 4.2 本体テスト（D-2〜D-4 通過後）

| ID | 内容 | 合否 |
|---|---|---|
| MK-1 | `make yuios` 成功・`make verify` で 56416バイト一致 | cmp 一致 |
| MK-2 | `make dhrystone` 成功・`make regress` で 826/48405/P:20 | 完全一致 |
| MK-3 | `make disk` で disk.img 生成（mkfs 正常） | 生成成功 |
| MK-4 | `make run` で `YUIOS Booted!` 起動 | 起動確認 |
| MK-5 | `make clean` 後に再 `make` で MK-1 再現（再現性） | 再現 |
| MK-6 | 本番ソース（fs/asm/c）が非改変であること（KY38） | diff ゼロ |

**L-A 対策**：単体（Makefile構文）が通っても実ビルドで初めて出る差異があるため、MK-1/MK-2 の
実ビルド・実 cmp・実回帰までを完了条件とする（設計の机上 OK では完了としない）。

---

## 5. KY（本設計に潜む危険）

| 危険 | 防止策 |
|---|---|
| **Make 各行が独立サブシェル→シェル変数が空展開（M-A 致命）** | **§2.2 `.ONESHELL:`/`SHELL`/`.SHELLFLAGS` を必須記述。D-3 で実証** |
| Make の `$` エスケープ誤りで sed パターンが変質し 56416 不一致 | MK-1 の cmp を必須ゲート化（J-2/J-5）。**D-2（`make -n`）で展開後文字列を目視（前段ゲート）** |
| 本番ソースを Makefile が直接上書き（KY38違反） | 中間は実験ファイル名（kf_r2*）に限定。本番 fs/asm/c は入力専用 |
| Dhrystone の3オプション欠落（L-B 再発） | D1 を変数化せず Makefile に固定文字列で明記。regress で即検出 |
| `disk.img` 汚染で誤デグレード（§6.10） | run は disk を依存に持つが、回帰時は `make disk` で作り直してから |
| **clean のワイルドカード過剰一致（E-B）** | **`rm -f $(FORTH_ASM)*` 等は kf_r2.asm.obj 等を巻き込む。意図内だが `make -n clean` で対象を確認してから実行。可能な範囲で明示ファイル名で列挙** |
| **ツール更新を Make が検知できず古い中間で誤回帰（J-7）** | **ツール差し替え時は `make clean` 必須（§3 J-7・D-4）** |

---

## 6. レビュー指摘への対応状況（v0.2・レビュー指摘書 v1.0 反映）

| 指摘 | 分類 | v0.2 での対応 | 反映箇所 |
|---|---|---|---|
| **M-A** | 必須 | `.ONESHELL:`/`SHELL`/`.SHELLFLAGS := -ec` を必須プリアンブルとして新設 | §2.2 |
| **M-B** | 必須 | D4 の `$` エスケープを `.ONESHELL` 前提で確定。最終文字列をコメント明記。`make -n`（D-2）を必須前段ゲート化 | §2.5 D4・§4.1 D-2 |
| **M-C** | 必須 | yuios 依存に mk_post1.sh 追加。ツール差し替え時 `make clean` 必須を J-7 として明記 | §2.4 依存・§3 J-7 |
| **E-A** | 新規 | REF_BIN を凍結退避品 `yuios_ref_road2_I3.bin` に変更（自己比較回避）。56416 の出所＝道2 I3 を明記 | §2.3 REF_BIN |
| **E-B** | 新規 | clean ワイルドカード過剰一致を KY 追記（`make -n clean` 確認・明示列挙推奨） | §5 KY |
| **C-1** | 確認 | E-A の凍結退避品方式を採用（レビュア推奨どおり） | §2.3 |
| **C-2** | 確認 | ファイル名 `Makefile`（カレント既定）で確定 | §2.1 既定 |
| **C-3** | 確認 | clean は disk.img を消さない（J-4）で確定 | §2.6・§3 J-4 |
| **D-1** | 検証 | D-2 を前段ゲートに追加し MK 群と合わせ過不足解消 | §4.1・§4.2 |
| **E-1** | 新規 | No.2 の将来 lnk23 解消を手順書§10 に追記する旨を**本工程の文書改版 ToDo に登録**（Step 8-B 完了時の手順書改版で反映。Step 8-F残/8-I との関係併記） | 下記 §7 |

## 7. 文書改版 ToDo（Step 8-B 実装完了時に実施・KY41）

| 文書 | 改版内容 |
|---|---|
| yuios_build_procedure | §10 No.1/4/5 を「Makefile で解決済」に更新。**E-1**：No.2 の将来 lnk23 クロス参照解消（Step 8-F残/8-I 関連）を §10 に追記。Makefile ビルド節を新設 |
| tool_version_ledger | Makefile・mk_post1.sh を成果物として登録 |
| HANDOVER（次工程用） | Step 8-B 完了状態・Makefile 運用を記載 |

---

*— YSD8800 Project / YUI OS / Step 8-B / v0.2 —*
```
