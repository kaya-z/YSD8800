\ kernel_forth.fs - YUI OS カーネル Forth 層
\ Version: 0.10.9   v0.10.8 + Step 5-6c FILE-WRITE-IMPL ロールバック実装
\ YSD8800 YUI OS Microkernel
\
\ ★★★ v0.10.9 追加点 (2026-06-02) Step 5-6c: FILE-WRITE-IMPL ロールバック ★★★
\   設計: yuios_ph4_filemgr_design_v1_9_1.md §6.4.1.5（REV-PH4-WRITE-003 GO）
\   内容: FILE-WRITE-IMPL 最終段 [M]（SB 書き戻し）の I/O 失敗時に、[L] で進めた
\         メモリ値（FS-NEXT-FREE/FS-FILE-COUNT）を巻き戻し、書込失敗時の一貫性を保証。
\   変更3点:
\     (1) [L'] ロールバック退避を [L] メモリ更新の直前に固定（KY26: 退避値=更新前の
\         旧値を構造的に保証）。FS-NEXT-FREE/FS-FILE-COUNT を FS-WR-OLD-NEXT/COUNT へ退避。
\     (2) [M] SB-LOAD 失敗枝に巻戻し追加（★論点①: SB-LOAD 失敗も巻戻し対象。実装は
\         [L] メモリ更新の後に [M] SB-LOAD があるため、SB-LOAD 失敗時もメモリは既に進む）。
\     (3) [M] SB-STORE 失敗枝に巻戻し追加。
\   巻戻し対象はメモリのみ（論点③）。ディスク DE（[K]済）は Phase 1 では戻さない
\   （巻戻しの巻戻し問題回避・残存リスクは設計書§4.4.2 既知制限）。
\   巻戻し枝は VARIABLE 間代入のみで SB-LOAD/SB-STORE を再呼出さない（KY4/KY25 非抵触）。
\   検証: D-2（机上検証＋正常系 …WVX・LBA6/LBA7 mismatch=0 の非回帰実機）。emu23 無改修。
\
\ ★★★ v0.10.8 修正 (2026-05-31) MEMCPY-B/MEMSET-B 完全再入化 ★★★
\   問題: 旧版はループ上限を FM-WK-LEN(グローバル)に置いていたため、ループ実行中の
\         タイマーIRQ→別タスク(DIR-FIND等)が FM-WK-LEN を上書きし、2セクタ目書込が
\         途中(2バイト)で切れていた (HANDOVER_CHAT37 問題3・出力末尾 小文字x)。
\   修正: 状態 (dptr/sptr/remain, dptr/val/remain) を全てデータスタックで回す方針へ。
\         グローバル変数 FM-WK-* を一切使わず完全再入可能化。R収支・D収支とも机上検証済。
\   波及: 本修正により MEMCPY-B/MEMSET-B は FM-WK-DST/SRC/LEN/VAL を破壊しなくなった。
\         各所コメント「MEMCPY-B が FM-WK を破壊」は実態と乖離（文書整備で更新予定）。
\
\ ★★★ v0.10.8 追加点 (2026-05-31) Step 5-6b: FILE-WRITE-IMPL 複数セクタ対応 ★★★
\ 設計書: yuios_ph4_filemgr_design_v1_9_1.md（レビュー承認済み・REV-PH4-WRITE-002 反映）
\
\ 追加・変更内容:
\   1. FILE-WRITE-IMPL を単一セクタ→複数セクタ対応へ拡張（§6.4.2）
\      - [C] size>512→E-INVAL ガード撤廃（負ガード size 0< のみ残す）
\      - [C2] n算出 新設: size==0 IF 1 ELSE (size+511) 9 RSHIFT THEN → FW-N
\        （★論点0=案A: size=0 は n=1 特例で 5-6a の C1 挙動を維持）
\      - [G] 空き容量チェックを一般形 (next_free + n - 1) >= total へ
\      - [I] データ書き込みをセクタ跨ぎループ化（FW-WRITTEN<FW-N 基準・★remain基準でない）
\        ・chunk=512 は src 直接 STOR-WRITE-1、chunk<512(端数/size0) は SECBUF 0埋め経由
\        ・ELSE枝は chunk を R 退避する確定形（DUP>R…R@ 0> IF…R@ MEMCPY-B THEN…R> DROP）
\          ※M1修正: 旧 OVER>R は FS-SECBUF を退避し破綻していた（REV-PH4-WRITE-002）
\        ・3変数同期更新(src+=512/LBA+=1/remain-=512/WRITTEN++)をループ末尾1箇所に集約(KY26)
\      - [J] DE sec_count を 1 固定 → FW-N（確保セクタ数）
\      - [L] メモリ更新を 1 → FW-N（FS-NEXT-FREE += n）
\      - [M] SB書戻しは変更なし（KY25 SB-LOAD 必須を維持）
\   2. VARIABLE FW-N/FW-LBA/FW-REMAIN/FW-WRITTEN 新設（§6.4.2.3・FM-WK 非依存）
\   3. テストバッファ再配置（案C・他領域非侵犯）:
\      - FT-RW-BUF=$EC00（1024B・src/dst時系列共用）新設
\      - FT-NAME-BUF $EC00→$5060、FT-STAT-BUF $EF00→$5070（FileMgr残余$5060-$50FF）
\      - 既存OPEN名前buf($ECA0)/READ dst($EE00)→新配置へ更新（回帰防止）
\   4. FILEMGR-TEST-TASK に FILE-WRITE-MULTI-TEST 追加（§8.4.6.6）
\      - size=1024 をパターン byte[i]=(i&$FF) で WRITE→汚染→OPEN→READ→サンプル点検証
\      - サンプル点 buf[0/511/512/513/1023] 一致なら 'X'（失敗 'x'）
\
\ Step 5-6b 期待出力: …QLORCWVX （5-6a の …QLORCWV に X 追加）
\ ★実装後重点確認: ①size=1024で buf[512]==$00(セクタ境界KY26) ②size=0特例n=1
\   ③LBA0 magic 'YUIFS' 保持(KY25) ④既存 …QLORCWV 維持(回帰)
\
\ ────────────────────────────────────────────────────────────
\ 以下、v0.10.7 までの履歴
\
\ ★★★ v0.10.7 追加点 (2026-05-30) Step 5-6a: FILE-WRITE-IMPL 実装 ★★★
\ 設計書: yuios_ph4_filemgr_design_v1_8_1.md（レビュー承認済み・REV-PH4-WRITE-001 反映）
\
\ 追加・変更内容:
\   1. NAME-COPY-16 ( dst src -- ) 新設（§6.4.1.2）
\      - dst を 16B 全 0 クリア → src を NAME-LEN バイトコピー（NUL終端は0埋めで確保）
\      - mkfs の DE name 形式（NUL 終端 16B）と整合。FM-WK 破壊
\   2. FILE-WRITE-IMPL ( arg2 arg1 arg0 tid -- ) 新規実装（§6.4.1.1・Step 5-6a）
\      - arg0=name_addr, arg1=src_addr, arg2=size。新規作成・単一セクタ(size<=512)
\      - 引数を FW-NAME/FW-SRC/FW-SIZE へ早期退避しデータスタックを浅く保つ
\      - 異常系: name長>15→E-NAMETOOLONG / size<0→E-INVAL / size>512→E-INVAL(5-6a限定)
\        / DIR-LOAD失敗→E-IOERR / 同名→E-EXIST / 空きDE無→E-NODIRSPC / 容量不足→E-NOSPC
\      - 書込順序厳守(§4.4.3): [I]データ→[K]ディレクトリ→[M]SB
\      - 端数0パディング: size<512 は SECBUF を MEMSET-B で0埋め→MEMCPY-B→STOR-WRITE-1
\      - DE 書込[J]: name(NAME-COPY-16)/size下位2B/size上位2B明示0(C3)/start/sec_count=1/flags
\      - メモリ更新[L]はディスク書込成功後に遅延（5-6a は実質ロールバック不要）
\      - ★KY25: [M] で必ず SB-LOAD→SECBUF+24/+26更新→SB-STORE（SECBUF二重用途の
\        LBA0破壊を防止。SB-LOAD は [I] の枝に依らず常に実行・C2）
\      - 5-6a はロールバックなし（[M] SB-STORE 失敗時のメモリ巻戻しは 5-6c で実装）
\   3. VARIABLE FW-DI/FW-START/FW-SIZE/FW-SRC/FW-NAME 新設（FM-WK 非依存）
\   4. FILE-DISPATCH に FILE-WRITE-OP ($0204) 分岐を追加
\   5. FILEMGR-TEST-TASK に FILE-WRITE-TEST 追加（§8.4.6.2）
\      - 新規 "wtest.txt" を size=6 "WRITE!" で WRITE → r0=0 なら 'W'
\
\ Step 5-6a 期待出力: 0A BC123MPDQLORCW （OPEN→READ→CLOSE→WRITE 順で …QLORC に W）
\ ★実装後確認(KY25): emu23 で disk.img の LBA0 magic 'YUIFS' 保持を確認すること
\
\ ────────────────────────────────────────────────────────────
\ 以下、v0.10.6 までの履歴
\
\ ★★★ v0.10.6 追加点 (2026-05-30) Step 5-5: FILE-READ-IMPL 実装 ★★★
\ 設計書: yuios_ph4_filemgr_design_v1_7_1.md（レビュー承認済み・REV-PH4-READ-001 反映）
\
\ 追加・変更内容:
\   1. POS>LBA ( pos start_sec -- lba sofs ) 新設（§6.10・純関数・WRITE 共用）
\      - lba=start_sec+(pos>>9)、sofs=pos AND $1FF。9 RSHIFT(÷512)/$1FF AND(mod512)
\      - OT-POS 等を更新しない純関数（WRITE 流用時の二重更新を構造排除・KY24派生）
\   2. FILE-READ-IMPL ( arg2 arg1 arg0 tid -- ) 新規実装（§6.3.1）
\      - 異常系ガード順序: fid(FID-VALID?)→size負(0<)→pos>=fsz(actual=0)→MIN
\        （符号付き演算の正しさを順序で担保・KY24）
\      - size 上限は DUP 0< IF E-INVAL（$8000以上を弾く・上限$7FFF・§4.2訂正/案1）
\      - ループ変数は専用 VARIABLE FR-*（MEMCPY-B が壊す FM-WK と分離・FM-WK非依存）
\      - セクタ跨ぎ転送: POS>LBA→STOR-READ-1(lba buf--r0)→MEMCPY-B、FS-SECBUF緩衝
\      - I/O エラー時 OT-POS 不変で E-IOERR（dst は部分書込みで不定・§4.3.3 C1）
\      - 戻り値 r0 = actual(0..$7FFF) / E-BADF / E-INVAL / E-IOERR
\   3. VARIABLE FR-REMAIN/FR-DST/FR-POS/FR-START/FR-ACTUAL/FR-SLOT 新設
\   4. FILE-DISPATCH に FILE-READ-OP ($0203) 分岐を追加
\   5. FILEMGR-TEST-TASK に FILE-READ-TEST 追加（§8.4.5.3・OPEN→READ→CLOSE 順）
\      - FT-FID の fid に size=16 で READ → r0=14 かつ FT-DST-BUF[0]=='H' なら 'R'
\
\ ★注意（Step 5-5 報告事項）: ysd8800.prim の PRIM PLUS-STORE (+!) は val を無視し
\   mem[addr] を 2 倍化するバグ（LDW B,[A]; ADD B,B）がある。kernel_forth での
\   +! 使用実績は皆無で露見していなかった。本実装では +! を使わず @ + ! 等価形で
\   状態前進を実装した。+! の修正は別途 prim 改修（ツール改修＝Dhrystone 回帰対象）
\   として報告する。
\
\ Step 5-5 期待出力: 0A BC123MPDQLORC （OPEN→READ→CLOSE 順のため …QLO R C）
\
\ ────────────────────────────────────────────────────────────
\ 以下、v0.10.5 までの履歴
\
\ ★★★ v0.10.5 追加点 (2026-05-30) Step 5-4: FILE-CLOSE-IMPL 実装 ★★★
\ 設計書: yuios_ph4_filemgr_design_v1_6_1.md（レビュー承認済み）
\
\ 追加・変更内容:
\   1. FILE-CLOSE-IMPL ( arg2 arg1 arg0 tid -- ) 新規実装
\      - 設計書 §6.9 確定版をそのまま落とし込み
\      - FID-VALID? 一本で fid 検査（負値・範囲外・未used を一括判定）
\      - 有効なら OT-USED を 0 に（! = (val addr --) 順序、§6.6）
\      - FS-DIRBUF/ディスクには触れない（RAMのみ・§4.3.2.4）
\      - 戻り値: r0 = E-OK(0) / E-BADF
\      - OT-USED 遷移点を OPEN(0→1)/CLOSE(1→0)の2箇所に限定（§5.3.2・KY19）
\   2. FILE-DISPATCH に FILE-CLOSE-OP ($0202) 分岐を追加
\   3. VARIABLE FT-FID 新設（テスト専用：OPEN で得た fid を CLOSE まで保持）
\   4. FILEMGR-TEST-TASK に FILE-CLOSE-TEST 追加（設計書 §8.4.4.3）
\      - OPEN の fid を FT-FID に保存 → その fid を CLOSE
\      - r0=0(E-OK) なら 'C'、それ以外 'c'
\
\ Step 5-4 期待出力: 0A BC123MPDQLOC
\
\ ────────────────────────────────────────────────────────────
\ 以下、v0.10.4 までの履歴
\ ────────────────────────────────────────────────────────────
\
\ ★★★ v0.10.4 追加点 (2026-05-30) Step 5-3: FILE-OPEN-IMPL 実装 ★★★
\ 設計書: yuios_ph4_filemgr_design_v1_6_1.md（レビュー承認済み）
\
\ 追加・変更内容:
\   1. FILE-OPEN-IMPL ( arg2 arg1 arg0 tid -- ) 新規実装
\      - 設計書 §6.8 案I 確定版（§6.8.3 v1.6.1）をそのまま落とし込み
\      - name長チェック(NAME-LEN>=16) → マウント → DIR-FIND → 空きスロット走査
\        (最小index方式・§5.3.3) → DE情報をスロット記録 → fid返却
\      - 見つけた fid・dir_index・走査i は R/データスタック保持（C2・ワーク変数不使用）
\      - スロット各フィールド書込は ! = (val addr --) 順序（§6.6・M1）
\      - 戻り値: r0=fid(0..3) / E-NAMETOOLONG / E-IOERR / E-NOENT / E-MFILE
\      - 新規 VARIABLE 追加なし（スタックのみで完結）
\   2. FILE-DISPATCH に FILE-OPEN-OP ($0201) 分岐を追加
\   3. FILEMGR-TEST-TASK に FILE-OPEN-TEST 追加（設計書 §8.4.4.2）
\      - "hello.txt" を OPEN（名前 buf = TEST-SRC-BUF+$A0）
\      - 最小index方式により r0=0(fid=0) なら 'O'、それ以外 'o'
\
\ Step 5-3 期待出力: 0A BC123MPDQLO
\
\ ────────────────────────────────────────────────────────────
\ 以下、v0.10.3 までの履歴
\ ────────────────────────────────────────────────────────────
\
\ ★★★ v0.10.3 追加点 (2026-05-29) Step 5-2: FILE-LIST-IMPL 実装 ★★★
\ 設計書: yuios_ph4_filemgr_design_v1_5_2.md
\
\ 追加・変更内容:
\   1. VARIABLE FM-WK-COUNT/REMAIN/PTR 追加 (FILE-LIST 専用、案P)
\      - MEMCPY-B が破壊する FM-WK-LEN/SRC/DST/VAL とは分離
\      - 設計書 §5.8 ワーク変数一覧・§6.7 案I 確定版に対応
\   2. FILE-LIST-IMPL ( arg2 arg1 arg0 tid -- ) 新規実装
\      - 設計書 §6.7.3 案I をそのまま落とし込み
\      - 4 RSHIFT で max_n 算出 (Force SLASH 未対応のため)
\      - 境界条件: buf_size=0 / buf_size<16 / FS未マウント / arg2≠0 全対応
\   3. FILE-DISPATCH ( arg2 arg1 arg0 op tid -- ) 新規実装
\      - 旧 FILE-DISPATCH-STAT を拡張 (STAT + LIST)
\      - 旧 FILE-DISPATCH-STAT は後方互換のため残置
\   4. FILEMGR-TASK が FILE-DISPATCH-STAT → FILE-DISPATCH に切替
\   5. FILEMGR-TEST-TASK に FILE-LIST-TEST 追加
\      - 試験 buf = TEST-DST-BUF + $100 (=$EF00, 256B、設計書 v1.5.2 訂正)
\      - 期待 r0=1 → 'L' 出力 (Step 5-2 完了条件)
\      - r0≠1 → 'l' 出力 (失敗識別)
\
\ Step 5-2 期待出力: 0A BC123MPDQ L
\
\ ★★★ v0.10.2i 追加点 (2026-05-24) ★★★
\ 真因仮説: STAT-IMPL の中の DIR-FIND が「DIR-LOAD 済み前提」で書かれているが、
\ FILEMGR-INIT-DBG では DIR-LOAD を呼んでいないため、FS-DIRBUF が初期化されないまま
\ DIR-FIND が呼ばれて何か不正な挙動を起こしている。
\ FILEMGR-INIT-DBG に DIR-LOAD を追加して動作を確認する。
\
\ ★★★ v0.10.0 追加点 (2026-05-23) ★★★
\ Ph.4 Step 4 (FS-MOUNT 単体動作確認) に必要な以下を v0.9.0 に追加:
\   1. FILEMGR-TASK 実装 (FILEMGR-INIT → 'M'/'m' 出力 → IPC4-RECV AGAIN ループ)
\   2. FILEMGR-START 実装 (TASK-CREATE で tid=4 起動)
\
\ ★★★ v0.10.1 追加点 (2026-05-24) ★★★
\ Ph.4 Step 4-6 LBA衝突対処 (案α):
\   STOR-TEST-TASK の S2 (WRITE) / S3 (READ) で使う LBA を 0 → 10 に変更。
\   理由: Ph.4 で LBA=0 がスーパーブロック専用領域となったため、
\         STOR-TEST が LBA=0 に "STOR_TST" を書き込むと FS-MOUNT の
\         MAGIC-CHECK が必ず失敗していた (HANDOVER_CHAT30 参照)。
\   LBA=10 はデータ領域 (LBA=4〜) 内で、最小ディスクサイズ 8KB (16セクタ) にも収まる。
\   3. OS-START から FILEMGR-START 呼出 (STOR-START の直後)
\
\ Step 4 期待出力: A BCP M  (M = FS-MOUNTED=1 確認)
\ 異常系 (未フォーマットディスク or ver不一致): A BCP m  (小文字 m)
\
\ 半製品マーカーの取扱い:
\   - 「★REVIEW★」「★TODO★」「★HOLE★」マーカー付き IMPL は Step 5 以降で対応
\   - 本版では FILE-DISPATCH 等の TODO 群は呼び出さず、IPC4-RECV で受信した
\     メッセージは黙って捨てて次の RECV に戻る (Step 5 で FILE-DISPATCH を実装)
\
\ 設計方針:
\   - IRQ0ハンドラ・コンテキストスイッチはアセンブラ（kernel.asm）
\   - 高レベルAPIはここで純粋Forthとして実装（移植性重視）
\   - ハードウェア依存部は CODE...END-CODE に隔離
\
\ v0.9.0-WIP: Ph.4 フラットFS + FileMgr 実装 (中断・半製品) (2026-05-21)
\       設計書: yuios_ph4_filemgr_design_v1_2.md (FIX 済)
\               yuios_memmap_design_v1_3.md     (FIX 済)
\               yuios_design_v2_3.md            (FIX 済)
\       前チャット: HANDOVER_CHAT26 → 本ファイル → HANDOVER_CHAT27
\       追加内容 (現時点で骨格コード化のみ・動作未検証):
\         - FileMgr 専用定数群 ($4800系、エラーコード $FE00台、OP コード $0201..$0208)
\         - 補助ワード: MAGIC-CHECK / NAME-LEN / NAME-EQ? / FID-VALID?
\                       MEMCPY-B / MEMSET-B / SLOT-ADDR / DE-ADDR
\         - STOR I/O ヘルパ: STOR-READ-1 / STOR-WRITE-1
\         - SBブロック操作: SB-LOAD / SB-STORE
\         - ディレクトリ: DIR-LOAD / DIR-STORE / DIR-FIND / DIR-FIND-FREE
\         - FS-MOUNT / FILEMGR-INIT
\         - FILE-REORDER-MSG / REPLY-OK
\         - FILE-OPEN-IMPL / FILE-CLOSE-IMPL (半製品)
\         - FILE-SEEK-IMPL / FILE-STAT-IMPL / FILE-LIST-IMPL (半製品)
\         - FILE-READ-IMPL (複雑・特に要再検証)
\       未着手 (HANDOVER_CHAT27 で対応):
\         - FILE-WRITE-IMPL / FILE-DELETE-IMPL
\         - FILE-DISPATCH / FILEMGR-TASK / FILEMGR-START
\         - FILEMGR-TEST-TASK / FILEMGR-TEST-START
\         - mkfs_yuifs.py
\       OS-START 修正 (HANDOVER_CHAT26 案B採用):
\         - UART-TEST tid: 旧4 → 5  (FileMgr=4 と衝突回避)
\         - STOR-TEST tid: 旧5 → 6  (FileMgr=4, ProcMgr=5 と衝突回避)
\         - FILEMGR-START 追加 (tid=4)
\         - FILEMGR-TEST-START 追加 (tid=7) ※未実装のためコメントアウト中
\       期待最終出力: ABCXD P Q
\
\ v0.8.5: Ph.3.5 実装フェーズ Step 6 — IPC4 Pool 方式の実装
\       2026-05-17 デバッグ完了: STOR-DISPATCH READ分岐SWAP削除（dst/LBA逆転修正）
\       設計書: yuios_ipc4_pool_design_v1_2.md
\       方針:
\       - Forth コード変更なし（API 完全互換 §7.2）
\       - アセンブラ側で IPC4_SEND/RECV/CALL を全面書き換え
\       工程: Ph.3.5-I-1 Step 6（HANDOVER_CHAT23.docx §4.3）
\
\ v0.8.4: Ph.3.5 実装フェーズ Step 5 — stack guard 領域の初期化
\       設計書: yuios_memmap_design_v1_1.md §4.1・§7.1・§7.4
\       方針:
\       - GUARD-BASE=$FC00, GUARD-SIZE=$40 CONSTANT 新設
\         (CHK-GUARD ワード実装（Step 8）で使用)
\       - _kstart での guard 初期化はアセンブラ側で実施（kernel.asm v0.12.4）
\       工程: Ph.3.5-I-1 Step 5（HANDOVER_CHAT23.docx §4.3）
\
\ v0.8.3: Ph.3.5 実装フェーズ Step 4 — KERN_SP 専用化
\       設計書: yuios_memmap_design_v1_1.md §4.1・§6.3・§7.1
\       方針:
\       - Forth 側の CONSTANT 追加: KERN-SP-TOP=$477E, KERN-SP-BASE=$4700
\       - コード変更なし（SP切替はアセンブラ側）
\       工程: Ph.3.5-I-1 Step 4（HANDOVER_CHAT23.docx §4.3）
\
\ v0.8.2: Ph.3.5 実装フェーズ Step 3 — タスクスタック完全分離
\       設計書: yuios_memmap_design_v1_1.md §6.4（スタック完全分離設計）
\       方針:
\       - CALLSTK-BASE: $FBCE → $F07F（tid=0 コールスタック頂上）
\       - DATASTK-BASE: $FB4E → $F87F（tid=0 データスタック頂上）
\       - TASK-STK-GAP: $0100 → $0080（1タスクあたり128B）
\       - コール領域 $F000-$F7FF とデータ領域 $F800-$FBFF が物理完全分離
\       工程: Ph.3.5-I-1 Step 3（HANDOVER_CHAT23.docx §4.3）
\
\ v0.8.1: Ph.3.5 実装フェーズ Step 2 — TCB 16タスク化
\       設計書: yuios_tcb_design_v1_2.md §4（MAX_TASKS=16拡張）
\       方針:
\       - TCB-POOL コメント: $4000-$427F(8×80B) → $4000-$44FF(16×80B=1280B)
\       - MAX-TASKS CONSTANT 新設（16）
\       - Forthコード内「8タスク」記述を更新
\       - TCBオフセット定数 TCB-A(8) 等は変更しない
\       工程: Ph.3.5-I-1 Step 2（HANDOVER_CHAT23.docx §4.3）
\
\ v0.8.0: Ph.3.5 実装フェーズ Step 1 — メモリマップアドレス定数の更新
\       設計書: yuios_memmap_design_v1_1.md（FIX 版）
\       方針:
\       - OS共有変数: $F0xx → $FCxx (OS共有変数領域 $FC40-$FC7F へ)
\         (タスクスタック領域 $F000-$FBFF の完全独立化)
\       - PAGE-BMP-LO/HI: $F010/$F012 → $FC40/$FC42
\       - MEM-TID-ADDR: $F014 → $FC44
\       - UART-RX-RING-BUF/HEAD/TAIL/COUNT/DRV-TID/WAIT-TID: $F020-$F038 → $FC46-$FC5E
\       - BC-STR: $F040 → $FC60
\       - STOR-DRV-TID/WAIT-TID/LAST-STAT: $F050/$F052/$F054 → $FC64/$FC66/$FC68
\       - TEST-SRC-BUF/DST-BUF: $E800/$EA00 → $EC00/$EE00
\       - カーネルワーク領域参照（インラインASM）: $42xx → $47xx
\       注意:
\       - $F000 CONSTANT PAGE-BMP-HI-INIT は実アドレスでなく値（変更しない）
\       - DATASTK-BASE 等スタック関係の変更は Step 3 で対応
\       - MAX-TASKS / TCB プール末尾の変更は Step 2 で対応
\       工程: Ph.3.5-I-1 Step 1（HANDOVER_CHAT23.docx §4.3 / §9.1）
\
\ v0.7.2: スタック衝突修正 + STOR-TEST 暴走防止 (HANDOVER_CHAT22 / Ph.3 暫定版)
\       1. DATASTK-BASE を $F9CE → $FB4E へ変更（kernel_v11.asm v0.11.3 と整合）
\          理由: tid=N+2 のコール範囲と tid=N のデータ範囲が重なるため
\       2. STOR-TEST-TASK 末尾に BEGIN AGAIN 追加（タスク終了時の暴走防止）
\          各 EXIT パスを「失敗マーカ + BEGIN AGAIN」に変更
\          失敗箇所識別: F2 (S2=WRITE), F3 (S3=READ), F4 (S4=比較不一致)
\       注意: 本修正は8タスク維持の暫定版。→ v0.8.1 で16タスク化正式化済み。
\            IPC4 競合バグ: Ph.3.5 Step 6〜7 で根本解決予定。
\

\ 設計方針:
\   - IRQ0ハンドラ・コンテキストスイッチはアセンブラ（kernel.asm）
\   - 高レベルAPIはここで純粋Forthとして実装（移植性重視）
\   - ハードウェア依存部は CODE...END-CODE に隔離
\
\ v0.1: TASK-ID, TASK-PRINT-ID をForth化
\ v0.2: TASK-WAKEUP, TASK-CREATE, MSG-SEND, MSG-RECV をForth化
\ v0.3: ISA2.3 v2.2.1メモリマップ対応
\ v0.4: kernel.asm v0.8対応（YUI OS v2.0 Ph.1 IPC拡張）
\       TCBサイズ 64B→80B / IPC4ワード追加
\ v0.5: YUI OS v2.0 Ph.2 メモリマネージャ実装
\       - ページビットマップ管理（$E200/$E202）
\       - BMP-INIT / BMP-BIT-SET / BMP-BIT-CLR / BMP-BIT@ / BMP-FREE-COUNT
\       - FIT-START / FREE-PGNO VARIABLE（2PICK代替: Force v1.3未対応のため）
\       - ALLOC-FIT? / BMP-MARK-USED / MEM-ALLOC-PAGES / MEM-FREE-PAGES
\       - REORDER-MSG-3 / MEMMGR-DISPATCH / MEMMGR-TASK / MEMMGR-START
\       - デモタスク削除 → MEM-TEST-TASK に置き換え
\ v0.6: YUI OS v2.0 Ph.3-A5 UARTドライバ実装
\       - UART定数追加（UART-RX, IRQ-STAT, IRQ-MASK, RXバッファ変数）
\       - UART-PUTC-IMPL / UART-PUTS-IMPL / UART-GETC-IMPL
\       - UART-DISPATCH / UART-DRV-TASK / UART-START
\       - UART-TEST-TASK / UART-TEST-START
\       - OS-START: MEMMGR-START → UART-START → UART-TEST-START
\ v0.7: YUI OS v2.0 Ph.3-B ストレージドライバ実装
\       設計書: yuios_ph3_storage_design_v1_2.md (+ soudan3.txt 解釈A適用)
\       - YSD8003 MMIO定数 (SD-CMD/SD-STAT/SD-LBA-LO/SD-DATA/SD-IRQ-CTRL等)
\       - ストレージ変数 (STOR-DRV-TID/STOR-WAIT-TID/STOR-LAST-STAT)
\       - BC-STR を $E230 → $E260 へ移動 (kernel_v11.asm と整合)
\       - SELF-IPC-VALID? (STOR-LAST-STAT @ 0<>) - IR1解決
\       - TASK-WAIT-IPC ワード新設 (ドライバ自身を寝かす)
\       - STOR-INIT / STOR-DISPATCH / STOR-DRV-TASK / STOR-START
\       - STOR-READ-IMPL / STOR-WRITE-IMPL / STOR-STAT-IMPL
\       - STOR-TEST-TASK / STOR-TEST-START
\       - OS-START: MEMMGR → UART → STOR → UART-TEST → STOR-TEST
\       - 【★ 解釈A適用】 STOR-WAIT-TID = ドライバ自身のtid (旧設計のclient_tidは誤り)
\         wake_stor_waiter は state=5(WAIT_IPC)→READY 遷移
\         (旧 kernel_v11.asm wake_stor_waiter の state==6 は v0.11.1 で v=5 に修正)
\ v0.7.1: A/B案適用 - 変数領域 Forthコード衝突回避（B案で全面移動）
\       問題: v0.7 で Forthコード末尾が $D817 → $E795 に肥大化し、
\            $E200-$E795 のカーネル変数を Forthコードが上書きする問題発生
\       対処（B案全面移動）:
\       - PAGE-BMP-LO/HI を $E200/$E202 → $F010/$F012 へ移動
\       - MEM-TID-ADDR を $E204 → $F014 へ移動
\       - UART-RX-RING-BUF/HEAD/TAIL/COUNT/DRV-TID/WAIT-TID を $F020-$F038 へ移動
\       - BC-STR を $E260 → $F040 へ移動
\       - STOR-DRV-TID/WAIT-TID/LAST-STAT を $F050/$F052/$F054 へ移動
\       - TEST-SRC-BUF/DST-BUF を $E800/$EA00 へ移動
\         (Forthコード末尾$E795とスタック最低$F3CEの間)
\ v0.7.2: スタック衝突修正 + STOR-TEST 暴走防止 (HANDOVER_CHAT22 / Ph.3 暫定版)
\       1. DATASTK-BASE を $F9CE → $FB4E へ変更（kernel_v11.asm v0.11.3 と整合）
\          理由: tid=N+2 のコール範囲と tid=N のデータ範囲が重なるため
\       2. STOR-TEST-TASK 末尾に BEGIN AGAIN 追加（タスク終了時の暴走防止）
\          各 EXIT パスを「失敗マーカ + BEGIN AGAIN」に変更
\          失敗箇所識別: F2 (S2=WRITE), F3 (S3=READ), F4 (S4=比較不一致)
\       注意: 本修正は8タスク維持の暫定版。→ v0.8.1 で16タスク化正式化済み。
\            IPC4 競合バグ（STOR-TEST F4停止）: Ph.3.5 Step 6〜7 で根本解決予定。

\ ============================================================
\ ハードウェア定数（移植時はここを変更）
\ ============================================================
$FC80 CONSTANT UART-TX
$FC82 CONSTANT UART-RX          \ v0.6: 受信データレジスタ追加
$FC84 CONSTANT UART-STAT
$FCB2 CONSTANT IRQ-STAT         \ v0.6: YSD8004 IRQ_STAT
$FCB4 CONSTANT IRQ-MASK         \ v0.6: YSD8004 IRQ_MASK

\ ============================================================
\ UART受信リングバッファ変数アドレス v0.8.0: $F020-$F038 → $FC46-$FC5E
\   v0.6: 新設 → v0.7.1: $F020-$F038 → v0.8.0: $FC46-$FC5E
\   理由: タスクスタック領域 $F000-$FBFF を完全独立化
\        OS共有変数領域 $FC40-$FC7F に集約 (memmap v1.1 §5.2)
\ yuios_ph3_uart_design_v1_2.docx §2.2 (要 v1.3 改版・Ph.3.5完了時に一括対応)
\ ============================================================
$FC46 CONSTANT UART-RX-RING-BUF \ 16Bリングバッファ本体 v0.8.0: $F020→$FC46
$FC56 CONSTANT UART-RX-HEAD     \ 書き込み位置（IRQハンドラが進める） v0.8.0: $F030→$FC56
$FC58 CONSTANT UART-RX-TAIL     \ 読み出し位置（ドライバが進める）   v0.8.0: $F032→$FC58
$FC5A CONSTANT UART-RX-COUNT    \ バッファ内バイト数（0-16）         v0.8.0: $F034→$FC5A
$FC5C CONSTANT UART-DRV-TID     \ UARTドライバタスクID格納アドレス   v0.8.0: $F036→$FC5C
$FC5E CONSTANT UART-WAIT-TID    \ UART_GETC待ちクライアントtid       v0.8.0: $F038→$FC5E

\ ============================================================
\ YSD8003 ストレージ MMIO（v0.7追加）
\ emu23_device_design_v1_2.docx §6
\ emu23_v103_design_v1_4.md §3
\ ============================================================
$FCA0 CONSTANT SD-CMD           \ 0=READ_SETUP 1=WRITE_SETUP 2=EXEC
$FCA2 CONSTANT SD-STAT          \ bit0=BUSY bit1=ERROR bit2=READY
$FCA4 CONSTANT SD-LBA-LO        \ LBA下位16bit
$FCA6 CONSTANT SD-LBA-HI        \ LBA上位16bit
$FCA8 CONSTANT SD-BUF-PTR       \ バッファポインタ(0-511)
$FCAA CONSTANT SD-DATA          \ PIOデータ(8bit)・自動BUF_PTR++
$FCAC CONSTANT SD-IRQ-CTRL      \ bit0=IRQ_EN bit1=ERR_EN
$FCAE CONSTANT SD-DISK-LO       \ 総セクタ数下位
$FCB0 CONSTANT SD-DISK-HI       \ 総セクタ数上位

\ ============================================================
\ ストレージ専用変数アドレス v0.8.0: $F050-$F054 → $FC64-$FC68
\   v0.7: $E230 → v0.7.1: $F050 → v0.8.0: $FC64 (OS共有変数領域)
\ yuios_ph3_storage_design_v1_2.md §2.2 (要 v1.3 改版・Ph.3.5完了時に一括対応)
\ ============================================================
$FC64 CONSTANT STOR-DRV-TID     \ ストレージドライバtid格納アドレス v0.8.0: $F050→$FC64
$FC66 CONSTANT STOR-WAIT-TID    \ EXEC完了待ちtid                  v0.8.0: $F052→$FC66
                                \ ★ 解釈A: ドライバ自身のtidが入る
$FC68 CONSTANT STOR-LAST-STAT   \ 最終SD_STAT値兼IRQ完了通知シグナル v0.8.0: $F054→$FC68
                                \ EXEC前0クリア・IRQ後に必ず非0(READY/ERROR)

\ ============================================================
\ ストレージ IPC4 op番号（v0.7追加）
\ yuios_ph3_storage_design_v1_2.md §6.1
\ ============================================================
$0501 CONSTANT STOR-READ-OP
$0502 CONSTANT STOR-WRITE-OP
$0503 CONSTANT STOR-STAT-OP

\ ============================================================
\ ストレージテスト用バッファ v0.8.0: $E800/$EA00 → $EC00/$EE00
\   v0.7.1: $E800/$EA00 → v0.8.0: $EC00/$EE00 (テスト領域 $EC00-$EFFF)
\   memmap v1.1 §5.4
\ ============================================================
$EC00 CONSTANT TEST-SRC-BUF     \ 512B 書き込み元 v0.8.0: $E800→$EC00
$EE00 CONSTANT TEST-DST-BUF     \ 512B 読み出し先 v0.8.0: $EA00→$EE00

\ ============================================================
\ UART IPC4 op番号（v0.6追加）
\ yuios_design_v2_0.docx §6.2 と整合
\ ============================================================
$0401 CONSTANT UART-PUTC-OP
$0402 CONSTANT UART-GETC-OP
$0403 CONSTANT UART-PUTS-OP

\ ============================================================
\ FileMgr 定数 (v0.9.0新設)
\ yuios_ph4_filemgr_design_v1_2.md §4.1 / §5.2 / §5.5
\ ★この節は確定済み・机上検証不要
\ ============================================================

\ --- FileMgr 専用変数 ($4800系、memmap v1.3 カーネル成長予約領域) ---
$4800 CONSTANT FILEMGR-TID-ADDR  \ FileMgr タスク ID 格納 (=4)
$4802 CONSTANT FS-MOUNTED        \ FS マウント状態 (0=未, 1=済)
$4804 CONSTANT FS-NEXT-FREE      \ next_free_sec キャッシュ
$4806 CONSTANT FS-FILE-COUNT     \ file_count キャッシュ
$4808 CONSTANT FS-TOTAL-SEC      \ total_sectors キャッシュ
$480A CONSTANT FS-WR-OLD-NEXT    \ FILE_WRITE ロールバック退避 (old_next_free)
$480C CONSTANT FS-WR-OLD-COUNT   \ FILE_WRITE ロールバック退避 (old_file_count)
$480E CONSTANT FS-FSVER          \ FSバージョン (上位=major 下位=minor)
$4820 CONSTANT FS-OPENTAB        \ オープンファイルテーブル (16B × 4スロット = 64B)
$4860 CONSTANT FS-SECBUF         \ 汎用セクタバッファ (512B)
$4A60 CONSTANT FS-DIRBUF         \ ディレクトリキャッシュ (1536B = 3セクタ)

\ --- FS レイアウト定数 (§5.5) ---
1     CONSTANT FS-DIR-START      \ ディレクトリ領域開始 LBA
3     CONSTANT FS-DIR-SECTORS    \ ディレクトリ領域セクタ数
32    CONSTANT FS-DIR-ENTRIES    \ ディレクトリエントリ総数
4     CONSTANT FS-DATA-START     \ データ領域開始 LBA
48    CONSTANT FS-DE-SIZE        \ ディレクトリエントリサイズ (B)
512   CONSTANT FS-SECSIZE        \ セクタサイズ (B)

\ --- ディレクトリエントリ内オフセット (§3.4) ---
0     CONSTANT DE-NAME           \ name (16B)
16    CONSTANT DE-SIZE           \ size (4B, u32, ただし下位16bitのみ運用)
20    CONSTANT DE-START-SEC      \ start_sec (2B)
22    CONSTANT DE-SEC-COUNT      \ sec_count (2B)
24    CONSTANT DE-FLAGS          \ flags (2B)
1     CONSTANT FLG-USED          \ flags bit0: 1=使用中

\ --- FILE_xxx OP コード (§4.1) ---
$0201 CONSTANT FILE-OPEN-OP
$0202 CONSTANT FILE-CLOSE-OP
$0203 CONSTANT FILE-READ-OP
$0204 CONSTANT FILE-WRITE-OP
$0205 CONSTANT FILE-SEEK-OP
$0206 CONSTANT FILE-STAT-OP
$0207 CONSTANT FILE-LIST-OP
$0208 CONSTANT FILE-DELETE-OP

\ --- エラーコード (§4.2、FS系 $FE00台) ---
$0000 CONSTANT E-OK
$FE01 CONSTANT E-NOENT           \ ファイル不存在
$FE02 CONSTANT E-NOSPC           \ ディスク空き容量不足
$FE03 CONSTANT E-MFILE           \ オープン数上限超過
$FE04 CONSTANT E-BADF            \ 不正な fid
$FE05 CONSTANT E-NAMETOOLONG     \ ファイル名 15 文字超
$FE06 CONSTANT E-EXIST           \ 同名ファイル既存
$FE07 CONSTANT E-NODIRSPC        \ ディレクトリエントリ空きなし
$FE08 CONSTANT E-IOERR           \ ストレージ I/O エラー
$FE09 CONSTANT E-INVAL           \ 引数不正
$FE0A CONSTANT E-FSVER           \ FS ver_major 不一致
$FE0B CONSTANT E-BUSY            \ open 中削除不可

\ --- オープンファイルテーブル スロット内オフセット (§5.3) ---
0     CONSTANT OT-USED           \ 1=使用中, 0=空き
2     CONSTANT OT-DIR-INDEX      \ DEインデックス
4     CONSTANT OT-START-SEC      \ ファイル先頭LBA
6     CONSTANT OT-SIZE           \ サイズ (4B、下位2Bを運用)
10    CONSTANT OT-POS            \ 論理オフセット (4B、下位2Bを運用)
16    CONSTANT OT-SLOT-SIZE      \ 1スロット 16B
4     CONSTANT FS-MAX-OPEN       \ 同時オープン上限

\ --- FILE_STAT 戻りバッファのオフセット (§4.3.5) ---
\ stat_buf レイアウト: +0=size(4B) +4=start_sec(2B) +6=sec_count(2B) +8=flags(2B) +10..(予約)

\ --- FileMgr テスト用バッファ (§8.3) ---
\ ★注意: $EC00/$EE00 は STOR-TEST と共有。FileMgr-TEST 実装時は時分割共用とする
$EC00 CONSTANT FT-NAME-BUF       \ テスト用ファイル名 "hello.txt"
$EC10 CONSTANT FT-SRC-BUF        \ 書き込みデータ (1セクタ未満)
$EE00 CONSTANT FT-DST-BUF        \ 読み出し先 (FILE_READ の dst)
$EF00 CONSTANT FT-STAT-BUF       \ FILE_STAT 結果
\ v0.10.8 (Step 5-6b・案C): 複数セクタ往復検証バッファ（§8.4.6.6）
\   FT-RW-BUF は src/dst 時系列共用の 1024B。テスト領域 $EC00-$EFFF（1KB）全域。
\   既存テスト（hello/wtest/no = TEST-SRC-BUF系 + FT-DST-BUF）は本テスト開始前に
\   完了するため、$EC00-$EFFF を時系列で再利用できる（案C の核心）。
\   name は FileMgr 残余 $5060-$50FF（FS-DIRBUF=$4A60+1536B=$505F の次・重複なし）。
$EC00 CONSTANT FT-RW-BUF         \ src/dst 共用 1024B（$EC00-$EFFF）
$5060 CONSTANT FT-NAME2-BUF      \ 5-6b 用ファイル名 "w1k.txt"（FileMgr残余・非侵犯確認済）

\ ============================================================
\ TCB定数（v0.4: 80Bレイアウト対応）
\ ============================================================
$4000 CONSTANT TCB-POOL     \ TCBプール先頭（$4000-$44FF: 16×80B=1280B） v0.8.1: 8→16タスク
80    CONSTANT TCB-SIZE
16    CONSTANT MAX-TASKS     \ v0.8.1新設: MAX_TASKS=16 (yuios_tcb_design_v1_2.md §4)
$F07E CONSTANT CALLSTK-BASE \ tid=0 コールスタック頂上 v0.8.2: $FBCE→$F07E (偶数化)
                            \ CALLSTK_TOP(tid) = $F07E + tid×$80 (tid SHL 7)
                            \ コール領域: $F000-$F7FF（16タスク×128B、実効126B）
$F87E CONSTANT DATASTK-BASE \ tid=0 データスタック頂上 v0.8.2: $FB4E→$F87E (偶数化)
                            \ DATASTK_TOP(tid) = $F87E + tid×$80 (tid SHL 7)
                            \ データ領域: $F800-$FBFF（16タスク×128B、実効126B）
$0080 CONSTANT TASK-STK-GAP \ タスク間スタック間隔 v0.8.2: $0100→$0080 (128B)

\ TCBオフセット（バイト）
0  CONSTANT TCB-STATE
2  CONSTANT TCB-PC
4  CONSTANT TCB-SP
6  CONSTANT TCB-DSP
8  CONSTANT TCB-A
12 CONSTANT TCB-FLAGS
16 CONSTANT TCB-IPC-MSG0   \ ipc_msg[0] opcode
18 CONSTANT TCB-IPC-MSG1   \ ipc_msg[1] arg0
20 CONSTANT TCB-IPC-MSG2   \ ipc_msg[2] arg1
22 CONSTANT TCB-IPC-MSG3   \ ipc_msg[3] arg2/result
24 CONSTANT TCB-IPC-VALID
26 CONSTANT TCB-IPC-SENDER

\ タスク状態定数
0 CONSTANT TASK-DEAD
1 CONSTANT TASK-READY
2 CONSTANT TASK-RUNNING
3 CONSTANT TASK-SLEEPING
4 CONSTANT TASK-WAIT-MSG
5 CONSTANT TASK-WAIT-IPC
6 CONSTANT TASK-WAIT-REPLY

\ カーネルワーク変数 v0.8.0: $4292→$4792 (frequently used 領域)
$4792 CONSTANT CUR-TASK-ADDR

\ KERN_SP 専用領域定数 v0.8.3新設 (yuios_memmap_design_v1_1.md §6.3)
$477E CONSTANT KERN-SP-TOP    \ カーネルスタック頂上（偶数）
$4700 CONSTANT KERN-SP-BASE   \ カーネルスタック底（canary $A55A 設置先）

\ stack guard 領域定数 v0.8.4新設 (yuios_memmap_design_v1_1.md §7.1・§7.4)
$FC00 CONSTANT GUARD-BASE     \ stack guard 領域先頭 ($FC00-$FC3F, 64B)
$0040 CONSTANT GUARD-SIZE     \ stack guard サイズ (64B = 32ワード)
$A55A CONSTANT GUARD-PATTERN  \ guard 初期値・検出パターン

\ ============================================================
\ MemMgr 定数 v0.8.0: $F010-$F014 → $FC40-$FC44 (OS共有変数領域)
\   v0.5: $E200/$E202/$E204 → v0.7.1: $F010/$F012/$F014 → v0.8.0: $FC40/$FC42/$FC44
\ ============================================================
$FC40 CONSTANT PAGE-BMP-LO      \ ビットマップ下位ワード（page 0-15）  v0.8.0: $F010→$FC40
$FC42 CONSTANT PAGE-BMP-HI      \ ビットマップ上位ワード（page 16-31） v0.8.0: $F012→$FC42
$FC44 CONSTANT MEM-TID-ADDR     \ MemMgr tid 格納アドレス             v0.8.0: $F014→$FC44
$C000 CONSTANT PAGE-POOL-BASE   \ ページプール先頭
32    CONSTANT PAGE-TOTAL        \ 総ページ数
28    CONSTANT PAGE-USER-MAX     \ ユーザ用ページ数（OS予約4ページ除く）
$F000 CONSTANT PAGE-BMP-HI-INIT \ HI初期値（page28-31=bit12-15=1）
                                \ ★この値はビットマップ値であって実アドレスでない（v0.8.0でも変更しない）
$0101 CONSTANT MEM-ALLOC-OP
$0102 CONSTANT MEM-FREE-OP
$0103 CONSTANT MEM-QUERY-OP

\ ============================================================
\ MemMgr 作業変数（v0.5追加）
\ Force v1.3 が 2PICK に未対応のため VARIABLE で代替
\ Force がカーネル変数領域に自動配置する
\ 注意: v0.8.0以降は OS共有変数領域（$FC40-$FC7F）以降に配置されることを確認
\       (旧 $F016 以降の前提は v0.8.0 で改められた)
\ ============================================================
VARIABLE FIT-START   \ ALLOC-FIT? / BMP-MARK-USED 用: start を退避
VARIABLE FREE-PGNO   \ MEM-FREE-PAGES 用: page_no を退避

\ ============================================================
\ アーキテクチャ層 CODE...END-CODE ブリッジ
\ ============================================================

CODE DI-OP
    DI
END-CODE
CODE EI-OP
    EI
END-CODE

CODE KERN-TASK-SLEEP
    JSR $01C0
END-CODE
CODE KERN-TASK-EXIT
    JSR $0460
END-CODE
CODE KERN-TASK-CREATE
    JSR $0520
END-CODE
CODE KERN-TASK-WAKEUP-ASM
    JSR $0380
END-CODE

\ IPC4 低レベルブリッジ
\ IPC4-SEND-ASM  ( msg3 msg2 msg1 msg0 tid -- )
CODE IPC4-SEND-ASM
    JSR $0740
END-CODE
\ IPC4-RECV-ASM  ( -- msg3 msg2 msg1 msg0 )
CODE IPC4-RECV-ASM
    JSR $07E0
END-CODE
\ IPC4-CALL-ASM  ( msg3 msg2 msg1 msg0 tid -- )
CODE IPC4-CALL-ASM
    JSR $08C0
END-CODE
\ IPC4-REPLY-ASM  ( r3 r2 r1 r0 tid -- )
CODE IPC4-REPLY-ASM
    JSR $0B00
END-CODE

\ ============================================================
\ TCB操作プリミティブ
\ ============================================================

\ TCBアドレス計算: tid → TCBアドレス
\ v0.4: tid*80 = (tid<<6) + (tid<<4)
: TCB-ADDR  ( tid -- addr )
    DUP  6 LSHIFT
    SWAP 4 LSHIFT
    +
    TCB-POOL + ;

: TCB-@  ( tid off -- val )  SWAP TCB-ADDR + @ ;
: TCB-!  ( val tid off -- )  SWAP TCB-ADDR + ! ;

: TCB-STATE@  ( tid -- state )  TCB-STATE TCB-@ ;
: TCB-STATE!  ( state tid -- )  TCB-STATE TCB-! ;

: TCB-IPC-VALID@   ( tid -- valid )   TCB-IPC-VALID  TCB-@ ;
: TCB-IPC-SENDER@  ( tid -- sender )  TCB-IPC-SENDER TCB-@ ;
: TCB-IPC-MSG0@    ( tid -- val )     TCB-IPC-MSG0   TCB-@ ;
: TCB-IPC-MSG1@    ( tid -- val )     TCB-IPC-MSG1   TCB-@ ;
: TCB-IPC-MSG2@    ( tid -- val )     TCB-IPC-MSG2   TCB-@ ;
: TCB-IPC-MSG3@    ( tid -- val )     TCB-IPC-MSG3   TCB-@ ;

\ ============================================================
\ UART出力
\ ============================================================
: emit-char  ( c -- )
    BEGIN UART-STAT @ 0= INVERT UNTIL
    UART-TX ! ;

: emit-nl  ( -- )  10 emit-char ;

\ ============================================================
\ TASK-ID  ( -- tid )
\ ============================================================
: TASK-ID  ( -- tid )
    CUR-TASK-ADDR @ ;

\ ============================================================
\ TASK-PRINT-ID  ( -- )
\ ============================================================
: TASK-PRINT-ID  ( -- )
    84 emit-char
    TASK-ID 48 + emit-char
    emit-nl ;

\ ============================================================
\ TASK-WAKEUP  ( tid -- )
\ v0.4: SLEEPING(3) / WAIT-IPC(5) → READY
\ ============================================================
: TASK-WAKEUP  ( tid -- )
    DUP TCB-STATE@
    DUP TASK-SLEEPING =
    SWAP TASK-WAIT-IPC =
    OR
    IF
        TASK-READY SWAP TCB-STATE!
    ELSE
        DROP
    THEN ;

\ ============================================================
\ TASK-CREATE  ( entry -- tid )
\ ============================================================
: TASK-CREATE  ( entry -- tid )
    KERN-TASK-CREATE ;

\ ============================================================
\ TASK-EXIT  ( -- )
\ ============================================================
: TASK-EXIT  ( -- )
    KERN-TASK-EXIT ;

\ ============================================================
\ TASK-SLEEP  ( -- )
\ ============================================================
: TASK-SLEEP  ( -- )
    KERN-TASK-SLEEP ;

\ ============================================================
\ IPC4ワード（v0.4）
\ ============================================================
: IPC4-SEND  ( msg3 msg2 msg1 msg0 tid -- )
    IPC4-SEND-ASM ;

: IPC4-RECV  ( -- msg3 msg2 msg1 msg0 )
    IPC4-RECV-ASM ;

: IPC4-CALL  ( msg3 msg2 msg1 msg0 tid -- r3 r2 r1 r0 )
    IPC4-CALL-ASM ;

: IPC4-REPLY  ( r3 r2 r1 r0 tid -- )
    IPC4-REPLY-ASM ;

\ IPC4-SENDER-DIRECT: DSPを使わずにsender tidを直接取得
\ CUR_TASK($4792)→tid→TCB[$4000+tid*80+26]を読む  v0.8.0: $4292→$4792 等
\ スタック上のデータを破壊しない
CODE IPC4-SENDER-DIRECT  ( -- tid )
    DI                       ; IRQ競合防止（L1_WK_TMP/L1_WK_C共有）
    STW  X, [$4788]          ; DSP退避（IRQ_WK_X流用）   v0.8.0: $4288→$4788
    LDW  A, [$4792]          ; A = CUR_TASK              v0.8.0: $4292→$4792
    STW  A, [$4786]          ; L1_WK_TMP = tid           v0.8.0: $4286→$4786
    LDW  B, #6
    SHL  A, B                ; A = tid*64
    STW  A, [$4784]          ; L1_WK_C                   v0.8.0: $4284→$4784
    LDW  A, [$4786]          ; A = tid                   v0.8.0: $4286→$4786
    LDW  B, #4
    SHL  A, B                ; A = tid*16
    LDW  B, [$4784]          ; B = tid*64                v0.8.0: $4284→$4784
    ADD  A, B                ; A = tid*80
    LDW  B, #$4000
    ADD  A, B                ; A = TCB addr
    MOV  X, A                ; X = TCB addr
    LDW  A, [X + #26]        ; A = TCB[+26] = ipc_sender
    LDW  X, [$4788]          ; DSP復元                   v0.8.0: $4288→$4788
    SUBI X, #2
    STW  A, [X]              ; push tid
    EI
END-CODE

: IPC4-SENDER  ( -- tid )
    TASK-ID TCB-IPC-SENDER@ ;

\ ============================================================
\ v0.5: メモリマネージャ（MemMgr）実装
\ ============================================================

\ ============================================================
\ ビットマップ操作ワード
\ ============================================================

\ BMP-INIT  ( -- )
\ ページビットマップ初期化
\ page 0-15: 全空き（$0000）
\ page 16-27: 空き、page 28-31: OS予約（$F000）
: BMP-INIT  ( -- )
    0                PAGE-BMP-LO !
    PAGE-BMP-HI-INIT PAGE-BMP-HI ! ;

\ BMP-BIT-SET  ( page_no -- )
\ 指定ページを使用中（bit=1）にセット
: BMP-BIT-SET  ( page_no -- )
    DUP 16 <
    IF
        1 SWAP LSHIFT
        PAGE-BMP-LO @ OR
        PAGE-BMP-LO !
    ELSE
        16 -
        1 SWAP LSHIFT
        PAGE-BMP-HI @ OR
        PAGE-BMP-HI !
    THEN ;

\ BMP-BIT-CLR  ( page_no -- )
\ 指定ページを空き（bit=0）にクリア
: BMP-BIT-CLR  ( page_no -- )
    DUP 16 <
    IF
        1 SWAP LSHIFT INVERT
        PAGE-BMP-LO @ AND
        PAGE-BMP-LO !
    ELSE
        16 -
        1 SWAP LSHIFT INVERT
        PAGE-BMP-HI @ AND
        PAGE-BMP-HI !
    THEN ;

\ BMP-BIT@  ( page_no -- flag )
\ 指定ページのビット状態を返す（0=空き、0以外=使用中）
: BMP-BIT@  ( page_no -- flag )
    DUP 16 <
    IF
        1 SWAP LSHIFT
        PAGE-BMP-LO @ AND
    ELSE
        16 -
        1 SWAP LSHIFT
        PAGE-BMP-HI @ AND
    THEN
    0= INVERT ;

\ BMP-FREE-COUNT  ( -- n )
\ 空きページ数を返す（全32ページスキャン）
\ page_no をRスタックで管理し、データスタックには count のみを置く
\ Force v1.3: BEGIN/WHILE後のA残骸問題を回避。REPEAT後DUP DROPでcount→A確定
: BMP-FREE-COUNT  ( -- n )
    0 >R             \ R=page_no=0
    0                \ count（データスタック上）
    BEGIN R@ PAGE-TOTAL < WHILE
        R@ BMP-BIT@ 0=
        IF 1+ THEN   \ 空きなら count++
        R> 1+ >R     \ page_no++
    REPEAT
    R> DROP          \ page_noをRから捨てる
    DUP DROP ;       \ Force TOS=A残骸対策: count を A に確定してRET

\ ============================================================
\ ページ割り当て補助ワード
\ ============================================================

\ ALLOC-FIT?  ( start n -- flag )
\ start から n ページ全てが空きか確認する
\ -1=全空き（成功）、0=失敗
: ALLOC-FIT?  ( start n -- flag )
    OVER FIT-START !         \ start を変数に退避
    0                        \ start n i=0
    BEGIN DUP OVER < WHILE   \ i < n
        FIT-START @ OVER +   \ start n i (start+i)
        BMP-BIT@             \ start n i bit
        IF                   \ 使用中→失敗
            DROP DROP        \ n i 捨て
            0 EXIT
        THEN
        1+                   \ i++
    REPEAT
    DROP DROP -1 ;           \ n i 捨て、-1（成功）を返す

\ BMP-MARK-USED  ( start n -- )
\ start から n ページを使用中にマーク
: BMP-MARK-USED  ( start n -- )
    OVER FIT-START !         \ start を変数に退避
    0                        \ start n i=0
    BEGIN DUP OVER < WHILE   \ i < n
        FIT-START @ OVER +   \ start n i (start+i)
        BMP-BIT-SET
        1+
    REPEAT
    DROP DROP DROP ;         \ start n i 捨て

\ ============================================================
\ MEM-ALLOC-PAGES  ( n -- addr )
\ n 連続ページを First Fit で割り当て
\ 戻り値: 先頭アドレス（失敗=0）
: MEM-ALLOC-PAGES  ( n -- addr )
    DUP 0=              IF DROP 0 EXIT THEN
    DUP PAGE-USER-MAX > IF DROP 0 EXIT THEN

    DUP >R                        \ R=n
    PAGE-USER-MAX SWAP -          \ max_start = 28-n

    0                             \ max_start start=0
    BEGIN
        DUP OVER > INVERT WHILE   \ start <= max_start
        DUP R@ ALLOC-FIT?
        IF
            DUP R@ BMP-MARK-USED  \ 使用中マーク
            256 * PAGE-POOL-BASE + \ addr = $C000 + start*256
            SWAP DROP             \ max_start 捨て
            R> DROP EXIT          \ addr を返す
        THEN
        1+                        \ start++
    REPEAT
    DROP DROP R> DROP 0 ;         \ 失敗: 0

\ ============================================================
\ MEM-FREE-PAGES  ( addr n -- )
\ addr から n ページを解放
\ ============================================================
: MEM-FREE-PAGES  ( addr n -- )
    DUP 0= IF DROP DROP EXIT THEN

    OVER PAGE-POOL-BASE -         \ n (addr-$C000)
    DUP 0< IF
        DROP DROP EXIT
    THEN
    8 RSHIFT                      \ n page_no
    DUP 255 > IF DROP DROP EXIT THEN

    DUP PAGE-USER-MAX >= IF
        DROP DROP EXIT
    THEN

    OVER FREE-PGNO !              \ n を退避
    OVER                          \ n page_no page_no
    FREE-PGNO @ +                 \ n page_no (page_no+n)
    PAGE-USER-MAX > IF
        DROP DROP EXIT
    THEN

    FREE-PGNO !                   \ n → FREE-PGNO
    FREE-PGNO @ SWAP              \ page_no n
    FREE-PGNO !                   \ page_no を確定退避、n はスタック

    0                             \ n i=0
    BEGIN DUP OVER < WHILE        \ i < n
        FREE-PGNO @ OVER +        \ n i (page_no+i)
        BMP-BIT-CLR
        1+
    REPEAT
    DROP DROP ;

\ ============================================================
\ IPC4 メッセージ整列ワード
\ ============================================================

\ REORDER-MSG-3  ( msg3 msg2 msg1 msg0 -- op arg0 arg1 )
: REORDER-MSG-3  ( msg3 msg2 msg1 msg0 -- arg1 arg0 op )
    \ msg0=op, msg1=arg0, msg2=arg1, msg3=不使用
    \ msg3 を捨てるため >R して NIP的処理
    >R >R >R     \ R: msg2 msg1 msg0 退避
    DROP         \ msg3を捨てる
    R> R> R> ;   \ msg2(arg1) msg1(arg0) msg0(op) を順に戻す → TOS=op

\ ============================================================
\ MemMgr サーバタスク
\ ============================================================

\ MEMMGR-DISPATCH  ( op arg0 arg1 client_tid -- )
: MEMMGR-DISPATCH  ( arg1 arg0 op client_tid -- )
    \ REORDER-MSG-3 出力 arg1 arg0 op(TOS)
    \ + IPC4-SENDER で client_tid push: arg1 arg0 op client_tid(TOS)
    \ ※実際の呼び出しでは MEMMGR-TASK 側で処理
    >R                            \ R=client_tid → arg1 arg0 op(TOS)

    \ --- MEM_ALLOC ($0101) ---
    DUP MEM-ALLOC-OP = IF
        DROP                      \ op を捨てる → arg1 arg0(TOS=pages)
        SWAP DROP                 \ arg1 を捨てる → arg0=pages(TOS)
        MEM-ALLOC-PAGES           \ addr
        >R
        0 0 0
        R>                        \ r0=addr
        R> IPC4-REPLY
        EXIT
    THEN

    \ --- MEM_FREE ($0102) ---
    DUP MEM-FREE-OP = IF
        DROP                      \ op を捨てる → arg1(n) arg0(addr)(TOS)
        SWAP                      \ arg0(addr) arg1(n)(TOS) ← MEM-FREE-PAGES の引数順
        MEM-FREE-PAGES
        0 0 0 0 R> IPC4-REPLY
        EXIT
    THEN

    \ --- MEM_QUERY ($0103) ---
    MEM-QUERY-OP = IF
        DROP DROP                 \ arg1 arg0 を捨てる
        BMP-FREE-COUNT            \ count
        >R
        0 0 0
        R>                        \ r0=count
        R> IPC4-REPLY
        EXIT
    THEN

    DROP DROP
    0 0 0 0 R> IPC4-REPLY ;

\ MEMMGR-TASK  ( -- )
: MEMMGR-TASK  ( -- )
    BMP-INIT
    BEGIN
        IPC4-RECV                 \ ( -- msg3 msg2 msg1 msg0 )
        IPC4-SENDER-DIRECT >R     \ R=tid（DSP不使用で安全取得）
        REORDER-MSG-3             \ ( -- op arg0 arg1 )
        R>                        \ ( -- op arg0 arg1 tid )
        MEMMGR-DISPATCH
    AGAIN ;

\ MEMMGR-START  ( -- )
CODE MEMMGR-TASK-ADDR  ( -- addr )
    SUBI X, #2
    LDW  A, #WORD_MEMMGR_TASK
    STW  A, [X]
END-CODE

: MEMMGR-START  ( -- )
    MEMMGR-TASK-ADDR TASK-CREATE
    MEM-TID-ADDR ! ;

\ ============================================================
\ MEM-TEST-TASK  ( -- )
\ 期待出力: M → 8（空き28の下1桁） → A → R
\ ============================================================
: MEM-TEST-TASK  ( -- )
    BEGIN
        0 TCB-ADDR TCB-STATE + @
        TASK-WAIT-IPC =
    UNTIL

    77 emit-char emit-nl          \ 'M'

    \ (1) MEM_QUERY
    0 0 0 MEM-QUERY-OP
    MEM-TID-ADDR @ IPC4-CALL
    >R DROP DROP DROP R>          \ r0(count)を残しr3 r2 r1をDROP
    \ 10進2桁表示 (count < 100 を前提)
    0 SWAP                        \ tens=0 count
    BEGIN DUP 10 >= WHILE
        10 - SWAP 1+ SWAP
    REPEAT                        \ tens ones
    SWAP 48 + emit-char           \ 十の位
    48 + emit-char emit-nl        \ 一の位

    \ (2) MEM_ALLOC
    0 0 2 MEM-ALLOC-OP
    MEM-TID-ADDR @ IPC4-CALL
    >R DROP DROP DROP R>          \ r0(addr)を残しr3 r2 r1をDROP
    DUP 0= IF
        DROP 70 emit-char
    ELSE
        65 emit-char
    THEN
    emit-nl

    \ (3) MEM_FREE
    >R
    0 2 R> MEM-FREE-OP
    MEM-TID-ADDR @ IPC4-CALL
    DROP DROP DROP DROP
    82 emit-char emit-nl          \ 'R'

    TASK-EXIT ;

\ ============================================================
\ v0.6: UARTドライバ実装
\ yuios_ph3_uart_design_v1_2.docx §4-§7
\ ============================================================

\ ------------------------------------------------------------
\ UART-INIT  ( -- )
\ UARTドライバ起動時初期化（§4.2）
\ バッファ変数は_kstartで初期化済み。ここではデバイスフラグのみクリア。
\ 順序: デバイスフラグクリア（IRQ有効化の前に必ず実行）
\ ------------------------------------------------------------
: UART-INIT  ( -- )
    0 UART-WAIT-TID !       \ 待機tid=0（なし）— 念のためリセット
    \ デバイス残留フラグクリア（IRQ有効化の前に必ず実行）
    2 UART-STAT !           \ UART_STAT WTC: RX_READYクリア
    1 IRQ-STAT  !           \ IRQ_STAT WTC: bit0(UART RX)クリア
    \ IRQ_MASKはリセット値 bit0=0(RX許可) なので変更不要
    ;

\ ------------------------------------------------------------
\ UART-PUTC-IMPL  ( char -- )
\ 1バイト送信（TX_READYポーリング待ち → MMIO書込）
\ yuios_ph3_uart_design_v1_2.docx §6.3
\ 注意: TX_READYポーリングは必須（HWフロー制御なし≠同期不要）
\ ------------------------------------------------------------
: UART-PUTC-IMPL  ( char -- )
    BEGIN UART-STAT @ 1 AND UNTIL   \ TX_READY=1 待ち
    UART-TX ! ;                     \ 1バイト送信

\ ------------------------------------------------------------
\ UART-PUTS-IMPL  ( addr -- )
\ NUL終端文字列送信
\ yuios_ph3_uart_design_v1_2.docx §6.4
\ ------------------------------------------------------------
: UART-PUTS-IMPL  ( addr -- )
    BEGIN
        DUP C@                      \ 1バイト読出
        DUP 0= IF                   \ NUL検出
            DROP DROP EXIT
        THEN
        UART-PUTC-IMPL
        1+
    AGAIN ;

\ ------------------------------------------------------------
\ UART-RX-POP  ( -- byte )
\ リングバッファから1バイト取得（COUNT>0が前提）
\ DI/EI保護は呼び出し元(UART-GETC-IMPL)が担う
\ 更新順序: TAIL先 → COUNT後（逆順禁止）
\ yuios_ph3_uart_design_v1_2.docx §3.4
\ ------------------------------------------------------------
: UART-RX-POP  ( -- byte )
    UART-RX-TAIL @              \ tail_idx
    UART-RX-RING-BUF +          \ &buf[tail]
    C@                          \ byte
    UART-RX-TAIL @ 1+ 15 AND    \ (tail+1) mod 16
    UART-RX-TAIL !              \ TAIL更新（先）
    UART-RX-COUNT @ 1-
    UART-RX-COUNT ! ;           \ COUNT更新（後）

\ ------------------------------------------------------------
\ UART-GETC-IMPL  ( tid -- )
\ 1バイト受信。バッファ空なら待機、非空なら即REPLY
\ レース対策: DI中にWAIT-TID設定→COUNT再チェック
\ yuios_ph3_uart_design_v1_2.docx §6.5
\ ------------------------------------------------------------
: UART-GETC-IMPL  ( tid -- )
    DI-OP                           \ クリティカルセクション開始

    UART-RX-COUNT @ 0= IF
        \ --- バッファ空: 待機登録 ---
        DUP UART-WAIT-TID !         \ tid保存

        \ --- 再チェック（レース対策 §6.5.2）---
        UART-RX-COUNT @ 0= IF
            \ DI中なのでIRQは来ていない。安全にWAIT状態へ
            EI-OP
            DROP                    \ tid消費（REPLYしない）
            EXIT                    \ クライアントはWAIT-REPLY継続
        ELSE
            \ DI直前にIRQが走ってCOUNTが増えた（理論上は到達しない）
            0 UART-WAIT-TID !       \ 待機キャンセル
            \ 下に流れてpop & REPLY
        THEN
    THEN

    \ --- バッファ非空: 即REPLY ---
    \ スタック: tid (TOS)
    UART-RX-POP                     \ ( tid -- tid byte ) TOS=byte
    EI-OP
    \ IPC4-REPLY ( r3 r2 r1 r0 tid -- ): 底→TOS = r3 r2 r1 r0 tid
    \ byte→r0(TOS直下), tid→TOS
    \ RS(LIFO): 後積み→先出し。byteを後に積む→先に出る→r0位置へ
    SWAP                             \ ( tid byte -- byte tid ) TOS=tid
    >R                               \ R:tid (先積み),  stack: byte
    >R                               \ R:tid byte (後積み),  stack: (empty)
    0 0 0                            \ stack: 0(r3) 0(r2) 0(r1), TOS=0
    R>                               \ R:tid → pop byte(後積み先出し): 0 0 0 byte(r0)
    R>                               \ pop tid: 0 0 0 byte tid(TOS) ✓
    IPC4-REPLY ;

\ ------------------------------------------------------------
\ UART-DISPATCH  ( arg1 arg0 op tid -- )
\ op番号によりPUTC/PUTS/GETCに分岐
\ yuios_ph3_uart_design_v1_2.docx §4.4
\ ------------------------------------------------------------
: UART-DISPATCH  ( arg1 arg0 op tid -- )
    >R                              \ R: tid

    DUP UART-PUTC-OP = IF           \ op == $0401
        DROP                        \ op捨て
        SWAP DROP                   \ arg1捨て（TOS=arg0=char）
        UART-PUTC-IMPL              \ ( char -- )
        0 0 0 0 R> IPC4-REPLY
        EXIT
    THEN

    DUP UART-PUTS-OP = IF           \ op == $0403
        DROP
        SWAP DROP                   \ TOS=arg0=addr
        UART-PUTS-IMPL              \ ( addr -- )
        0 0 0 0 R> IPC4-REPLY
        EXIT
    THEN

    UART-GETC-OP = IF               \ op == $0402
        DROP DROP                   \ arg0/arg1不使用
        R> UART-GETC-IMPL           \ ( tid -- ) REPLY内部で実施
        EXIT
    THEN

    \ 未知op
    DROP DROP
    0 0 0 0 R> IPC4-REPLY ;

\ ------------------------------------------------------------
\ UART-DRV-TASK  ( -- )
\ UARTドライバメインタスク（§4.3パターン）
\ ------------------------------------------------------------
: UART-DRV-TASK  ( -- )
    UART-INIT
    BEGIN
        IPC4-RECV                   \ ( -- msg3 msg2 msg1 msg0 )
        DI-OP                       \ v0.7.3: race対策 - sender確定まで割込み禁止
        IPC4-SENDER-DIRECT >R       \ R: client_tid
        EI-OP                       \ v0.7.3: 割込み再許可
        REORDER-MSG-3               \ ( -- arg1 arg0 op )
        R>                          \ ( -- arg1 arg0 op tid )
        UART-DISPATCH
    AGAIN ;

\ ------------------------------------------------------------
\ UART-START  ( -- )
\ UARTドライバタスクを生成し、tidをUART-DRV-TIDに格納
\ MEMMGR-STARTの後、ユーザタスク作成より前に呼ぶこと
\ ------------------------------------------------------------
CODE UART-DRV-TASK-ADDR  ( -- addr )
    SUBI X, #2
    LDW  A, #WORD_UART_DRV_TASK
    STW  A, [X]
END-CODE

: UART-START  ( -- )
    UART-DRV-TASK-ADDR TASK-CREATE  \ ( -- tid )
    UART-DRV-TID ! ;                \ tidをUART-DRV-TIDに格納

\ ============================================================
\ v0.6: UARTテストタスク
\ 期待出力: ABCXD
\ yuios_ph3_uart_design_v1_2.docx §7
\ ============================================================

\ テスト用文字列 "BC\0" は kernel.asm v0.12.0 の $FC60 に配置
\ v0.7: $E230→$E260 → v0.7.1: $F040 → v0.8.0: $FC60（OS共有変数領域）
\ yuios_ph3_storage_design_v1_2.md §2.1
$FC60 CONSTANT BC-STR

: UART-TEST-TASK  ( -- )
    \ T1: PUTC 'A'($41)
    \ IPC4-CALL ( msg3 msg2 msg1 msg0 tid -- r3 r2 r1 r0 )
    \ msg0=op, msg1=arg0(char), msg2=arg1(unused), msg3=unused
    0 0 $41 UART-PUTC-OP  UART-DRV-TID @  IPC4-CALL
    DROP DROP DROP DROP

    \ T2: PUTS "BC"
    \ msg0=op, msg1=arg0(addr), msg2=arg1(unused), msg3=unused
    0 0 BC-STR UART-PUTS-OP  UART-DRV-TID @  IPC4-CALL
    DROP DROP DROP DROP

    \ T3-T4: GETC（バッファ空→ブロック、IRQで起床）
    0 0 0 UART-GETC-OP  UART-DRV-TID @  IPC4-CALL
    \ ( -- r3 r2 r1 r0 ) r0=受信文字
    SWAP DROP SWAP DROP SWAP DROP   \ r0のみ残す

    \ T5: 受信文字をエコーバック
    \ スタック: char (TOS) — GETCで受け取った文字
    \ msg0=op, msg1=arg0(char), msg2=0, msg3=0 の順に積む
    >R                               \ R:char, stack: empty
    0 0                              \ msg3=0, msg2=0
    R>                               \ msg3=0, msg2=0, msg1=char (TOS=char)
    UART-PUTC-OP                     \ msg0=UART-PUTC-OP
    UART-DRV-TID @                   \ tid
    IPC4-CALL
    DROP DROP DROP DROP

    \ T6: 完了マーカー 'D'($44)
    0 0 $44 UART-PUTC-OP  UART-DRV-TID @  IPC4-CALL
    DROP DROP DROP DROP

    BEGIN AGAIN ;                   \ 完了後は無限ループで停止待ち

CODE UART-TEST-TASK-ADDR  ( -- addr )
    SUBI X, #2
    LDW  A, #WORD_UART_TEST_TASK
    STW  A, [X]
END-CODE

: UART-TEST-START  ( -- )
    UART-TEST-TASK-ADDR TASK-CREATE
    DROP ;                          \ tidは不要なのでDROP

\ ============================================================
\ v0.7: ストレージドライバ実装
\ yuios_ph3_storage_design_v1_2.md (+ soudan3.txt 解釈A適用)
\ ============================================================

\ ------------------------------------------------------------
\ TASK-WAIT-IPC ワード（ドライバ自身を寝かす）v0.7新規
\ kernel_v11.asm $1100 の TASK_WAIT_IPC_ENTRY を呼び出す
\
\ ★ 解釈A: ドライバ自身が WAIT_IPC で寝る
\   IRQ1 の wake_stor_waiter から WAIT_IPC→READY で起こされる
\
\ ※ "TASK-WAIT-IPC" という名前は CONSTANT 5 と区別される
\   (CONSTANTはタスク状態定数、こちらはエントリワード)
\ ------------------------------------------------------------
CODE TASK-WAIT-IPC-ENTRY  ( -- )
    JSR $1100                       \ TASK_WAIT_IPC_ENTRY
END-CODE

\ ------------------------------------------------------------
\ SELF-IPC-VALID?  ( -- flag )  v0.7新規
\ STOR-LAST-STAT @ 0<> なら IRQ完了済（true）
\ yuios_ph3_storage_design_v1_2.md §5.5.2 / IR1解決
\ ------------------------------------------------------------
: SELF-IPC-VALID?  ( -- flag )
    STOR-LAST-STAT @ 0<> ;

\ ------------------------------------------------------------
\ STOR-INIT  ( -- )  v0.7新規
\ ドライバ初期化（STOR-DRV-TASK起動時に1回実施）
\ yuios_ph3_storage_design_v1_2.md §4.2
\ ------------------------------------------------------------
: STOR-INIT  ( -- )
    0 STOR-WAIT-TID !               \ 待機tid=0
    0 STOR-LAST-STAT !              \ ステータス初期化（シグナル兼用）
    0 SD-IRQ-CTRL !                 \ IRQ_CTRL 初期は無効
    \ YSD8004 IRQ_MASK の bit1 (STOR) を許可（=0）
    IRQ-MASK @ $FFFD AND IRQ-MASK ! ;

\ ------------------------------------------------------------
\ STOR-READ-IMPL  ( dst LBA tid -- )  v0.7新規
\ レビュー指摘 重大1/2/3/4 + review10 IR1/IR2 全反映版
\ ★ 解釈A適用: STOR-WAIT-TID にはドライバ自身のtid を入れる
\ yuios_ph3_storage_design_v1_2.md §4.4
\ ------------------------------------------------------------
: STOR-READ-IMPL  ( dst LBA tid -- )
    >R                              \ R: tid（client_tid）

    \ ★ G1: WAIT-TID ガード（重大1: BUSY返却）
    STOR-WAIT-TID @ 0= INVERT IF
        \ 既に他タスクが待機中 → BUSY返却
        DROP DROP                   \ dst, LBA 捨て
        -2 0 0 0 R> IPC4-REPLY      \ r0=-2 (BUSY)
        EXIT
    THEN

    \ stack: dst LBA

    \ G2: LBA設定（Phase1: 16bit）
    DUP SD-LBA-LO !                 \ ( -- dst LBA )
    DROP                            \ ( -- dst )
    0 SD-LBA-HI !

    \ G3: READ_SETUP
    0 SD-CMD !                      \ 0 = READ_SETUP

    \ ★ G3': STOR-LAST-STAT クリア（IR2）
    \ IRQ完了通知シグナルとして使うため、EXEC前に必ず0クリア
    0 STOR-LAST-STAT !

    \ ★ G4: WAIT-TID 設定（IRQ より前に必ず）
    \ ★ 解釈A: ドライバ自身のtid を入れる（旧設計のR@=client_tidは誤り）
    TASK-ID STOR-WAIT-TID !

    \ G5: IRQ_CTRL 有効化（§4.7 冪等性ルール準拠）
    1 SD-IRQ-CTRL !

    \ G6: EXEC 発行（emu23 v1.03: 512cycle後にIRQ1発火予約）
    2 SD-CMD !

    \ ★★★ G7-G9: IRQレース対策（重大2）
    \ パターン: DI → STAT再チェック → 既に非0なら起床済→WAITスキップ → EI+WAIT
    DI-OP                           \ 割込禁止（短時間）

    \ ★ G8: 自TCBの完了状態を再チェック（STAT非0で判定）
    SELF-IPC-VALID? IF
        \ 既にIRQ完了済（STAT非0） → WAITしない
        EI-OP
    ELSE
        \ まだIRQ来ていない → WAIT-IPCで寝る
        \ TASK-WAIT-IPC内部でEIされる前提（_sched_common経由）
        TASK-WAIT-IPC-ENTRY               \ ドライバ自身が寝る → IRQから起こされる
    THEN

    \ ★ R2: STAT 確認（重大4: ドライバ側で確認）
    \ ここでSTOR-LAST-STATは必ず非0（IRQ完了済保証）
    STOR-LAST-STAT @
    DUP $0004 AND 0= IF             \ bit2 (READY) が 0 ならエラー
        DROP                        \ STAT捨て
        DROP                        \ dst捨て
        \ ★ KY11: 全EXITパスでWAIT-TIDクリア
        0 STOR-WAIT-TID !
        -1 0 0 0 R> IPC4-REPLY      \ r0=-1 (ERROR)
        EXIT
    THEN
    DROP                            \ STAT捨て (READY確認済)

    \ ★ R3: SD_DATA → dst へ 512B 転送
    \ stack: dst
    \ BUF_PTR は EXEC 時に 0 にリセット済
    \ Force v1.2 は DO/LOOP 未対応のため BEGIN/WHILE/REPEAT で実装
    \
    \ ループ内で dst を pointer のように1ずつ進める方式:
    \   dst を残し、書込ごとに dst ← dst+1
    \   終了条件は count==0
    \ stack使用: TOS=count, 下=ptr
    \
    512                             \ stack: dst count=512
    BEGIN
        DUP 0 >
    WHILE
        \ stack: dst count
        SWAP                        \ stack: count dst
        SD-DATA @                   \ stack: count dst byte
        OVER C!                     \ dst[0] = byte (stack: count dst)
        1 +                         \ stack: count dst+1
        SWAP                        \ stack: dst+1 count
        1 -                         \ stack: dst+1 count-1
    REPEAT
    DROP                            \ count捨て
    DROP                            \ dst捨て (stack: empty)

    \ ★ R4: WAIT-TID 解放（最後）
    0 STOR-WAIT-TID !

    \ 成功応答 r0=0
    0 0 0 0 R> IPC4-REPLY ;

\ ------------------------------------------------------------
\ STOR-WRITE-IMPL  ( src LBA tid -- )  v0.7新規
\ ★ 解釈A適用: STOR-WAIT-TID にはドライバ自身のtid を入れる
\ yuios_ph3_storage_design_v1_2.md §4.5
\ ------------------------------------------------------------
: STOR-WRITE-IMPL  ( src LBA tid -- )
    >R                              \ R: tid（client_tid）

    \ ★ G1: BUSY ガード
    STOR-WAIT-TID @ 0= INVERT IF
        DROP DROP
        -2 0 0 0 R> IPC4-REPLY
        EXIT
    THEN

    \ stack: src LBA

    \ G2: LBA設定
    DUP SD-LBA-LO !
    DROP                            \ stack: src
    0 SD-LBA-HI !

    \ G3: WRITE_SETUP
    1 SD-CMD !                      \ 1 = WRITE_SETUP

    \ ★ G3': STOR-LAST-STAT クリア（IR2）
    0 STOR-LAST-STAT !

    \ ★ W3-pre: src → SD_DATA 512B 転送（EXEC前）
    \ BUF_PTR は WRITE_SETUP では自動リセットされないため明示
    \ ★【KY5/IR4】 0 SD-BUF-PTR ! は絶対に忘れないこと
    \ Force v1.2 は DO/LOOP 未対応のため BEGIN/WHILE/REPEAT で実装
    0 SD-BUF-PTR !
    \ stack: src
    512                             \ stack: src count=512
    BEGIN
        DUP 0 >
    WHILE
        \ stack: src count
        SWAP                        \ stack: count src
        DUP C@                      \ stack: count src byte (下位8bit)
        SD-DATA !                   \ BUF_PTR自動++ (stack: count src)
        1 +                         \ stack: count src+1
        SWAP                        \ stack: src+1 count
        1 -                         \ stack: src+1 count-1
    REPEAT
    DROP                            \ count捨て
    \ stack: src+512 (進めたsrcポインタ、後でDROP)

    \ ★ G4: WAIT-TID 設定
    \ ★ 解釈A: ドライバ自身のtid を入れる
    TASK-ID STOR-WAIT-TID !

    \ G5: IRQ_CTRL 有効化
    1 SD-IRQ-CTRL !

    \ G6: EXEC 発行
    2 SD-CMD !

    \ ★ G7-G9: IRQレース対策（READと同じ）
    DI-OP
    SELF-IPC-VALID? IF
        EI-OP
    ELSE
        TASK-WAIT-IPC-ENTRY               \ ドライバ自身が寝る
    THEN

    \ ★ R2: STAT 確認
    STOR-LAST-STAT @
    DUP $0004 AND 0= IF
        DROP DROP
        \ ★ KY11: ERRORパスでもWAIT-TIDクリア
        0 STOR-WAIT-TID !
        -1 0 0 0 R> IPC4-REPLY
        EXIT
    THEN
    DROP

    \ ★ R4: WAIT-TID 解放
    DROP                            \ src捨て
    0 STOR-WAIT-TID !

    \ 成功応答
    0 0 0 0 R> IPC4-REPLY ;

\ ------------------------------------------------------------
\ STOR-STAT-IMPL  ( tid -- )  v0.7新規
\ IRQ待ちなしで即座に SD_STAT を返す
\ yuios_ph3_storage_design_v1_2.md §4.6
\ ------------------------------------------------------------
\ IPC4-REPLY ( r3 r2 r1 r0 tid -- )
\ msg0(r0)=stat, msg1=msg2=msg3=0 として REPLY する
: STOR-STAT-IMPL  ( tid -- )
    \ スタック: tid
    >R                              \ R: tid, stack: empty
    SD-STAT @                       \ stack: stat
    >R                              \ R: tid stat, stack: empty
    0 0 0                           \ stack: 0(r3) 0(r2) 0(r1)
    R>                              \ stack: 0 0 0 stat (TOS=stat=r0)
    R>                              \ stack: 0 0 0 stat tid (TOS=tid)
    IPC4-REPLY ;

\ ------------------------------------------------------------
\ STOR-DISPATCH  ( arg1 arg0 op tid -- )  v0.7新規
\ op番号によりREAD/WRITE/STATに分岐
\ yuios_ph3_storage_design_v1_2.md §4.3
\ ------------------------------------------------------------
: STOR-DISPATCH  ( arg1 arg0 op tid -- )
    >R                              \ R: tid

    DUP STOR-READ-OP = IF
        DROP                        \ op捨て
        \ v0.12.6: 余計なSWAPを削除（chatlog修正の再適用）
        \ DROP後 stack: arg1(dst) arg0(LBA), 底→TOS = dst LBA
        \ STOR-READ-IMPL ( dst LBA tid -- ) は底→TOS = dst LBA tid を要求
        \ R> で tid を戻せば dst LBA tid ✓（SWAP不要）
        R>                          \ stack: dst LBA tid
        STOR-READ-IMPL              \ 内部でIPC4-REPLY
        EXIT
    THEN

    DUP STOR-WRITE-OP = IF
        DROP
        \ stack: arg1(src) arg0(LBA), TOS=LBA
        R>                          \ stack: src LBA tid
        STOR-WRITE-IMPL
        EXIT
    THEN

    STOR-STAT-OP = IF
        DROP DROP                   \ arg0 arg1 捨て
        R> STOR-STAT-IMPL           \ ( tid -- ) でREPLY
        EXIT
    THEN

    \ 未知op
    DROP DROP                       \ arg0 arg1 捨て
    -1 0 0 0 R> IPC4-REPLY ;

\ ------------------------------------------------------------
\ STOR-DRV-TASK  ( -- )  v0.7新規
\ ストレージドライバメインタスク（§4.1パターン）
\ yuios_ph3_storage_design_v1_2.md §4.1
\ ------------------------------------------------------------
: STOR-DRV-TASK  ( -- )
    STOR-INIT
    BEGIN
        IPC4-RECV                   \ ( -- msg3 msg2 msg1 msg0 )
        DI-OP                       \ v0.7.3: race対策 - sender確定まで割込み禁止
        IPC4-SENDER-DIRECT >R       \ R: client_tid
        EI-OP                       \ v0.7.3: 割込み再許可
        REORDER-MSG-3               \ ( -- arg1 arg0 op )
        R>                          \ ( -- arg1 arg0 op tid )
        STOR-DISPATCH
    AGAIN ;

\ ------------------------------------------------------------
\ STOR-START  ( -- )  v0.7新規
\ ストレージドライバタスクを生成し、tidをSTOR-DRV-TIDに格納
\ UART-STARTの後、ユーザタスク作成より前に呼ぶこと
\ ------------------------------------------------------------
CODE STOR-DRV-TASK-ADDR  ( -- addr )
    SUBI X, #2
    LDW  A, #WORD_STOR_DRV_TASK
    STW  A, [X]
END-CODE

: STOR-START  ( -- )
    STOR-DRV-TASK-ADDR TASK-CREATE  \ ( -- tid )
    STOR-DRV-TID ! ;                \ tidをSTOR-DRV-TIDに格納

\ ============================================================
\ v0.7: ストレージテストタスク
\ 期待出力: ABCXD の後にスペース+'P'
\ yuios_ph3_storage_design_v1_2.md §7
\ ============================================================
: STOR-TEST-TASK  ( -- )
    \ S0: スペース出力（区切り）
    0 0 $20 UART-PUTC-OP UART-DRV-TID @ IPC4-CALL
    DROP DROP DROP DROP

    \ S1: src_buf にパターン書き込み（最初の8B: "STOR_TST"）
    $53 TEST-SRC-BUF       C!       \ 'S'
    $54 TEST-SRC-BUF 1 +   C!       \ 'T'
    $4F TEST-SRC-BUF 2 +   C!       \ 'O'
    $52 TEST-SRC-BUF 3 +   C!       \ 'R'
    $5F TEST-SRC-BUF 4 +   C!       \ '_'
    $54 TEST-SRC-BUF 5 +   C!       \ 'T'
    $53 TEST-SRC-BUF 6 +   C!       \ 'S'
    $54 TEST-SRC-BUF 7 +   C!       \ 'T'

    \ S2: STOR_WRITE LBA=10 (v0.10.1: 案α LBA衝突対処、LBA=0 はスーパーブロック専用)
    \ IPC4-CALL ( msg3 msg2 msg1 msg0 tid -- r3 r2 r1 r0 )
    \ msg2=arg1(src), msg1=arg0(LBA), msg0=op
    0 TEST-SRC-BUF 10 STOR-WRITE-OP STOR-DRV-TID @ IPC4-CALL
    >R DROP DROP DROP R>            \ r0のみ残す
    0= INVERT IF
        0 0 $46 UART-PUTC-OP UART-DRV-TID @ IPC4-CALL  \ 'F'
        DROP DROP DROP DROP
        $32 UART-PUTC-IMPL          \ v0.7.2: '2' = S2失敗
        BEGIN AGAIN                 \ v0.7.2: EXIT→暴走を回避
    THEN

    \ S3: STOR_READ LBA=10 → dst_buf (v0.10.1: 案α LBA衝突対処)
    0 TEST-DST-BUF 10 STOR-READ-OP STOR-DRV-TID @ IPC4-CALL
    >R DROP DROP DROP R>
    0= INVERT IF
        0 0 $46 UART-PUTC-OP UART-DRV-TID @ IPC4-CALL
        DROP DROP DROP DROP
        $33 UART-PUTC-IMPL          \ v0.7.2: '3' = S3失敗
        BEGIN AGAIN
    THEN

    \ S4: src と dst の最初の8B を比較
    \ Force v1.2 は DO/LOOP 未対応のため BEGIN/WHILE/REPEAT で実装
    \ stack使用: i (0..7)
    0
    BEGIN
        DUP 8 <
    WHILE
        \ stack: i
        DUP TEST-SRC-BUF + C@       \ stack: i src[i]
        OVER TEST-DST-BUF + C@      \ stack: i src[i] dst[i]
        <> IF
            DROP                    \ i捨て
            0 0 $46 UART-PUTC-OP UART-DRV-TID @ IPC4-CALL  \ 'F'
            DROP DROP DROP DROP
            $34 UART-PUTC-IMPL      \ v0.7.2: '4' = S4不一致
            BEGIN AGAIN
        THEN
        1 +
    REPEAT
    DROP                            \ i捨て

    \ S5: 全致 → 'P' 出力
    0 0 $50 UART-PUTC-OP UART-DRV-TID @ IPC4-CALL  \ 'P'
    DROP DROP DROP DROP
    BEGIN AGAIN ;                   \ v0.7.2: タスク終了暴走防止

CODE STOR-TEST-TASK-ADDR  ( -- addr )
    SUBI X, #2
    LDW  A, #WORD_STOR_TEST_TASK
    STW  A, [X]
END-CODE

: STOR-TEST-START  ( -- )
    STOR-TEST-TASK-ADDR TASK-CREATE
    DROP ;                          \ tidは不要なのでDROP

\ ============================================================
\ OS-START  ( -- )  v0.7: Ph.3-B対応メインエントリ
\ 起動順序: MEMMGR-START → UART-START → STOR-START → UART-TEST-START → STOR-TEST-START
\ その後ルートタスクは待機ループ
\ yuios_ph3_storage_design_v1_2.md §7.3
\ ============================================================
\ ------------------------------------------------------------
\ [HYP5-DIAG] PUTC-HEX1  ( nibble -- )  下位4bitをhex1桁で出力
\ ------------------------------------------------------------
: PUTC-HEX1  ( n -- )
    $0F AND
    DUP 10 < IF $30 + ELSE $37 + THEN
    UART-PUTC-IMPL ;

\ [HYP5-DIAG] PUTC-HEX4  ( w -- )  16bitをhex4桁で出力
: PUTC-HEX4  ( w -- )
    DUP 12 RSHIFT PUTC-HEX1
    DUP  8 RSHIFT PUTC-HEX1
    DUP  4 RSHIFT PUTC-HEX1
                  PUTC-HEX1 ;

\ [HYP5-DIAG] DIAG-STR-TID  ( -- )  STOR-DRV-TID を [STR=XXXX] 形式で出力
: DIAG-STR-TID  ( -- )
    $5B UART-PUTC-IMPL              \ '['
    $53 UART-PUTC-IMPL              \ 'S'
    $54 UART-PUTC-IMPL              \ 'T'
    $52 UART-PUTC-IMPL              \ 'R'
    $3D UART-PUTC-IMPL              \ '='
    STOR-DRV-TID @ PUTC-HEX4
    $5D UART-PUTC-IMPL              \ ']'
    ;

\ [HYP8-DIAG] DIAG-ALL-TIDS  ( -- )  全タスクtidを出力
: DIAG-ALL-TIDS  ( -- )
    $5B UART-PUTC-IMPL              \ '['
    $55 UART-PUTC-IMPL              \ 'U'
    $3D UART-PUTC-IMPL              \ '='
    UART-DRV-TID @ PUTC-HEX4
    $2C UART-PUTC-IMPL              \ ','
    $53 UART-PUTC-IMPL              \ 'S'
    $3D UART-PUTC-IMPL              \ '='
    STOR-DRV-TID @ PUTC-HEX4
    $5D UART-PUTC-IMPL              \ ']'
    ;

\ ====================================================================
\ ★★★ v0.9.0-WIP: Ph.4 FileMgr (半製品・机上検証必須) ★★★
\ ====================================================================
\ 設計書: yuios_ph4_filemgr_design_v1_2.md
\
\ 重要警告:
\   - 本ブロックは未検証コードを含みます。HANDOVER_CHAT27.md §4「再検証必須
\     ワード一覧」を必ず確認してください。
\   - 現状はビルドが通らない可能性があります (FILE-DISPATCH / FILEMGR-TASK
\     / FILEMGR-START / FILEMGR-TEST-TASK が未実装プレースホルダのため、
\     OS-START からの参照が解決しません)。
\   - 次回作業では:
\       1. ★REVIEW★ マーカー付きの半製品ワードを机上検証 → 必要に応じ再実装
\       2. ★TODO★ マーカー付きのワードを実装
\       3. ダミー FILEMGR-TASK でビルド可能性を先に確認 (案δ思想)
\       4. その後 IMPL を1つずつ追加
\
\ Force v1.2 制約 (HANDOVER_CHAT27 §5 で詳述):
\   - DO/LOOP 不使用 → BEGIN/WHILE/REPEAT のみ
\   - LOCALS 不使用、2PICK / ROLL 不使用
\   - R スタック多段重ね (3段以上) は事故りやすい → VARIABLE 代替推奨
\   - IPC4 スタック効果: ( msg3 msg2 msg1 msg0 tid -- r3 r2 r1 r0 )
\                       msg0/r0 が TOS
\
\ ====================================================================

\ --------------------------------------------------------------------
\ FileMgr ワーク変数 (Force が自動配置)
\ Force v1.2: 2PICK 未対応のため、ループ変数は VARIABLE で代替する
\ (MemMgr の FIT-START / FREE-PGNO と同じ流儀)
\ --------------------------------------------------------------------
VARIABLE FM-WK-DST          \ MEMCPY-B / MEMSET-B 用: dst 退避
VARIABLE FM-WK-SRC          \ MEMCPY-B 用: src 退避
VARIABLE FM-WK-LEN          \ MEMCPY-B / MEMSET-B 用: len 退避
VARIABLE FM-WK-VAL          \ MEMSET-B 用: 充填値退避
VARIABLE FM-WK-A            \ 汎用ワーク A
VARIABLE FM-WK-B            \ 汎用ワーク B
VARIABLE FM-WK-C            \ 汎用ワーク C
\ v0.10.3 (Step 5-2 案P): FILE-LIST-IMPL 専用変数（MEMCPY-B が破壊する
\ FM-WK-LEN/SRC/DST/VAL とは分離。設計書 v1.5.2 §5.8・§6.7 参照）
VARIABLE FM-WK-COUNT        \ FILE-LIST 書き込み済み件数（戻り値）
VARIABLE FM-WK-REMAIN       \ FILE-LIST 残り書込可能枠（max_n カウントダウン）
VARIABLE FM-WK-PTR          \ FILE-LIST 次の書き込み先ポインタ
\ v0.10.6 (Step 5-5): FILE-READ-IMPL 専用ループ変数（設計書 §6.3.1）。
\   MEMCPY-B が破壊する FM-WK-DST/SRC/LEN/VAL とは分離した専用変数とすることで、
\   ループ内 MEMCPY-B 呼び出しでループ状態が壊れないことを保証する（FM-WK 非依存・
\   FILE-LIST 案P と同一思想・kaizen 原則26）。REPLY-OK の FM-WK-A/B 破壊とも独立。
VARIABLE FR-REMAIN          \ FILE-READ 残り転送バイト数
VARIABLE FR-DST             \ FILE-READ 次の書き込み先ポインタ d
VARIABLE FR-POS             \ FILE-READ 現在の論理オフセット pos
VARIABLE FR-START           \ FILE-READ ファイル先頭 LBA（ループ不変）
VARIABLE FR-ACTUAL          \ FILE-READ 実読み込み量（戻り値 actual）
VARIABLE FR-SLOT            \ FILE-READ 当該 fid のスロット先頭アドレス（OT-POS 書戻し用）
\ v0.10.7 (Step 5-6a): FILE-WRITE-IMPL 専用（設計書 §6.4.1）。
\   MEMCPY-B/MEMSET-B/DIR-FIND-FREE が破壊する FM-WK と分離した専用変数。
\   di（空き DE index）は DIR-FIND-FREE 直後に FW-DI へ退避し、後続の
\   NAME-COPY-16（MEMCPY-B 経由で FM-WK 破壊）と干渉させない（§6.4.1.4-3）。
VARIABLE FW-DI              \ FILE-WRITE 空き DE index
VARIABLE FW-START           \ FILE-WRITE start_sec（= 確保した先頭 LBA）
VARIABLE FW-SIZE            \ FILE-WRITE size（端数判定・DE 書込で再利用）
VARIABLE FW-SRC             \ FILE-WRITE src_addr
VARIABLE FW-NAME            \ FILE-WRITE name_addr
\ v0.10.8 (Step 5-6b): 複数セクタ書き込みループ用（§6.4.2.3・FM-WK 非依存・KY26）
VARIABLE FW-N               \ 必要セクタ数 n=ceil(size/512)。size==0 は n=1 特例
VARIABLE FW-LBA             \ 書込中の物理 LBA（start から +1 しながら進む）
VARIABLE FW-REMAIN          \ 残バイト数（512 ずつ減算・負可）
VARIABLE FW-WRITTEN         \ 書込済みセクタ数（ループ終了判定 FW-WRITTEN < FW-N）
VARIABLE FW-CHUNK           \ v0.10.8b: 今周のchunk(Forceループ内IF/ELSE値残し回避用)
\ v0.10.5 (Step 5-4): FILEMGR-TEST-TASK 専用。OPEN で得た fid を CLOSE まで保持。
\ テストタスク(tid=7)専用ワークで、FileMgr の FM-WK 系とは独立（共有による
\ REPLY-OK の FM-WK-A/B 破壊の影響を受けないため安全）。
VARIABLE FT-FID             \ テスト用：FILE-OPEN-TEST が得た fid を保持

\ --------------------------------------------------------------------
\ 補助ワード群 (§6.6)
\ --------------------------------------------------------------------

\ MEMCPY-B  ( dst src len -- )                          ★v0.10.8 完全再入化★
\ 副作用: dst[0..len-1] 書き換えのみ。★グローバル変数を一切使用しない★
\ 前提  : dst/src 領域が len バイト確保、重複なし
\ 設計  : 状態 ( dptr sptr remain ) を全てデータスタック上で回す（方針イ）。
\         旧版は上限を FM-WK-LEN（グローバル）に置いたため、ループ中の
\         タイマーIRQ→別タスクが FM-WK-LEN を上書きし2セクタ目が途中で切れた
\         (HANDOVER_CHAT37 問題3)。本版はグローバル不使用で完全再入可能。
\ R収支  : ループ内 >R(remain)…DUP>R(dptr)…R>(dptr)…R>(remain) で前後0（机上検証済）
\ MEMCPY-B  ( dst src len -- )                    ★v0.10.8 真の完全再入化(>R不使用)★
\ 副作用: dst[0..len-1] 書き換えのみ。★グローバル変数・リターンスタックを一切使用しない★
\ 前提  : dst/src 領域が len バイト確保、重複なし
\ 設計  : 状態 ( dptr sptr remain ) を全てデータスタック上で回す。>R を一切使わない。
\         旧>R使用版はループ途中状態がリターンスタック(コールスタック)上に乗るため、
\         ループ中のタイマーIRQ→タスク切替時のコンテキスト保存/復帰(SP±4)と干渉し、
\         第1セクタが385バイトで切れた(決定論的)。本版は全状態をDスタックに置くため、
\         IRQ切替時も saved_x(DSP) 退避だけで途中状態が完全保護される(DI不要・根本解決)。
\ R収支  : >R/R> 不使用。リターンスタックは JSR/RET のみ使用（途中状態を載せない）。
\ D収支  : ループ不変形 ( dptr sptr remain ) 維持。最大深さ5要素(2DUP直後)。終了後3DROP。
: MEMCPY-B  ( dst src len -- )
    BEGIN  DUP 0>  WHILE                    \ remain>0 か（TOS=remain を判定）
                                            \ D:( dptr sptr remain )
        ROT ROT                             \ D:( remain dptr sptr )  remainをボトム退避(-ROT)
        2DUP                                \ D:( remain dptr sptr dptr sptr )
        C@                                  \ D:( remain dptr sptr dptr byte )  src[i]読出
        SWAP                                \ D:( remain dptr sptr byte dptr )  C!=( byte addr )
        C!                                  \ D:( remain dptr sptr )  dst[i]=byte（原本保持）
        1 +                                 \ D:( remain dptr sptr+1 )  sptr++
        SWAP                                \ D:( remain sptr+1 dptr )
        1 +                                 \ D:( remain sptr+1 dptr+1 ) dptr++
        SWAP                                \ D:( remain dptr+1 sptr+1 ) dptr/sptr順に戻す
        ROT                                 \ D:( dptr+1 sptr+1 remain )  remainをTOSへ
        1 -                                 \ D:( dptr+1 sptr+1 remain-1 ) remain--
    REPEAT
    DROP DROP DROP ;                        \ 残 dptr sptr remain(=0) を捨てる（収支0）

\ MEMSET-B  ( dst val len -- )                    ★v0.10.8 真の完全再入化(>R不使用)★
\ 副作用: dst[0..len-1] 書き換えのみ。★グローバル変数・リターンスタックを一切使用しない★
\ 設計  : 状態 ( dptr val remain ) を全てデータスタック上で回す。>R を一切使わない。
\         MEMCPY-B と同型(src読出の代わりに val 書込)。IRQ切替時も saved_x で完全保護。
\ R収支  : >R/R> 不使用。D収支: ループ不変形 ( dptr val remain ) 維持。終了後3DROP。
: MEMSET-B  ( dst val len -- )
    BEGIN  DUP 0>  WHILE                    \ remain>0 か（TOS=remain を判定）
                                            \ D:( dptr val remain )
        ROT ROT                             \ D:( remain dptr val )  remainをボトム退避(-ROT)
        2DUP                                \ D:( remain dptr val dptr val )
        SWAP                                \ D:( remain dptr val val dptr )  C!=( byte=val addr )
        C!                                  \ D:( remain dptr val )  dst[i]=val（原本保持）
        SWAP                                \ D:( remain val dptr )
        1 +                                 \ D:( remain val dptr+1 )  dptr++
        SWAP                                \ D:( remain dptr+1 val )  dptr/val順を戻す
        ROT                                 \ D:( dptr+1 val remain )  remainをTOSへ
        1 -                                 \ D:( dptr+1 val remain-1 ) remain--
    REPEAT
    DROP DROP DROP ;                        \ 残 dptr val remain(=0) を捨てる（収支0）

\ NAME-LEN  ( name-addr -- len )                              ★REVIEW★
\ NULL終端文字列の長さ。最大16で打ち切り (15文字超なら 16 を返す)
\ 副作用: なし
: NAME-LEN  ( name-addr -- len )
    0 >R                                    \ R: i = 0
    BEGIN
        R@ 16 <                             \ i < 16
        OVER R@ + C@ 0= INVERT               \ かつ name[i] != 0
        AND
    WHILE
        R> 1 + >R
    REPEAT
    DROP                                    \ name-addr 捨てる
    R> ;                                    \ i を返す

\ NAME-EQ?  ( addr1 addr2 -- flag )                           ★REVIEW★
\ 16B 以内 NULL 終端文字列の一致判定 (両方が同位置で NULL なら eq)
\ 副作用: FM-WK-A/B/C/DST 破壊
\ 検証点: ループの「早期脱出」を done フラグで実現しているが、Force v1.2
\         で意図通り動くか確認。代替案として「最初の不一致で flag=0、
\         以降の比較もスキップ」する単純実装も検討
: NAME-EQ?  ( addr1 addr2 -- flag )
    FM-WK-A !                               \ FM-WK-A = addr2
    FM-WK-B !                               \ FM-WK-B = addr1
    1 FM-WK-C !                             \ FM-WK-C = 1 (eq候補)
    0 FM-WK-DST !                           \ FM-WK-DST = done flag
    0 >R                                    \ R: i = 0
    BEGIN  R@ 16 <  WHILE
        FM-WK-DST @ 0= IF                   \ 未確定の間だけ比較
            FM-WK-B @ R@ + C@                \ name1[i]
            FM-WK-A @ R@ + C@                \ name2[i]
            OVER OVER = IF
                DROP                         \ name2[i] 捨てる
                0= IF                        \ name1[i] == 0 ?
                    1 FM-WK-DST !            \ done (eq確定)
                THEN
            ELSE
                DROP DROP
                0 FM-WK-C !
                1 FM-WK-DST !                \ done (ne確定)
            THEN
        THEN
        R> 1 + >R
    REPEAT
    R> DROP
    FM-WK-C @ ;

\ MAGIC-CHECK  ( buf-addr -- flag )                           ★REVIEW★
\ buf 先頭 8B が "YUIFS\0\0\0" か照合
\ 副作用: なし
\ 検証点: 連続 IF...THEN の入れ子が Force v1.2 で正しくコンパイルされるか
\         (EXIT がネスト深い IF 内で正しく動くかは特に要確認)
: MAGIC-CHECK  ( buf-addr -- flag )
    DUP    C@ $59 = IF                      \ 'Y'
    DUP 1+ C@ $55 = IF                      \ 'U'
    DUP 2 + C@ $49 = IF                      \ 'I'
    DUP 3 + C@ $46 = IF                      \ 'F'
    DUP 4 + C@ $53 = IF                      \ 'S'
    DUP 5 + C@ 0  = IF
    DUP 6 + C@ 0  = IF
    DUP 7 + C@ 0  = IF
        DROP 1 EXIT                          \ 全一致
    THEN THEN THEN THEN THEN THEN THEN THEN
    DROP 0 ;                                 \ 不一致

\ FID-VALID?  ( fid -- flag )                                 ★REVIEW★
\ fid が 0〜3 (FS-MAX-OPEN-1) かつ used==1 か
\ 検証点: 0< / >= が Force v1.2 で使えるか確認。代替: 0 < / DUP < 等
: FID-VALID?  ( fid -- flag )
    DUP 0< IF DROP 0 EXIT THEN
    DUP FS-MAX-OPEN >= IF DROP 0 EXIT THEN
    OT-SLOT-SIZE *                           \ fid * 16
    FS-OPENTAB +                              \ slot addr
    OT-USED + @
    0= INVERT ;

\ SLOT-ADDR  ( fid -- slot-addr )
: SLOT-ADDR  ( fid -- addr )
    OT-SLOT-SIZE *  FS-OPENTAB + ;

\ DE-ADDR  ( index -- de-addr )
: DE-ADDR  ( index -- addr )
    FS-DE-SIZE *  FS-DIRBUF + ;

\ --------------------------------------------------------------------
\ POS>LBA  ( pos start_sec -- lba sofs )    ★v0.10.6 新設 / 設計書 §6.10
\ 論理オフセット pos → 物理 LBA / セクタ内オフセット sofs 変換。
\   lba  = start_sec + (pos >> 9)   \ = start_sec + pos/512
\   sofs = pos AND $1FF             \ = pos mod 512
\ 純関数：OT-POS を含むいかなる状態も更新しない（副作用なし）。
\ Force は / mod 未対応のため 512=2^9 を利用し 9 RSHIFT / $1FF AND で実装。
\ RSHIFT は ysd8800.prim L184 で SHR(論理シフト)＝符号なし。READ/WRITE 共用。
\ --------------------------------------------------------------------
: POS>LBA  ( pos start_sec -- lba sofs )
    OVER 9 RSHIFT +        \ ( pos lba )   lba = start_sec + (pos>>9)
    SWAP $1FF AND ;        \ ( lba sofs )  sofs = pos AND $1FF

\ --------------------------------------------------------------------
\ NAME-COPY-16  ( dst src -- )              ★v0.10.7 新設 / 設計書 §6.4.1.2
\ src の name を dst へ NUL 込みでコピーし、16B 内の残りを 0 埋めする。
\ mkfs の DE name 形式（NUL 終端 16B・§7）と整合させるため、まず dst を
\ 16B 全 0 クリア → src を NAME-LEN バイトコピー（NUL 終端は 0 埋めで自然に確保）。
\ 副作用: FM-WK-DST/SRC/LEN/VAL 破壊（MEMSET-B/MEMCPY-B 経由）。
\ FILE-WRITE-IMPL の DE name 書き込み [J] で使用。
\ --------------------------------------------------------------------
: NAME-COPY-16  ( dst src -- )
    OVER 0 16 MEMSET-B     \ dst を 16B 全 0 クリア（OVER で dst 複製。( dst src ) 維持）
    \ src(TOS) の長さを測る。★DUP で src を複製する（OVER だと dst を測る誤り）
    DUP NAME-LEN           \ ( dst src len )  len = NAME-LEN(src)、最大16
    MEMCPY-B ;             \ MEMCPY-B(dst src len): dst へ src を len バイトコピー

\ --------------------------------------------------------------------
\ STOR I/O ヘルパ
\ --------------------------------------------------------------------

\ STOR-READ-1  ( lba buf -- r0 )                              ★REVIEW★
\ 1セクタを STOR_READ。戻り値 r0 (0=OK, 非0=エラー) を返す。
\ 副作用: buf に 512B 書き込み。r1〜r3 は捨てる。
\ 検証点: IPC4-CALL スタック並び (msg3 msg2 msg1 msg0 tid) の組み立てが
\         正しいか。特に >R >R >R 0 R> R> R> の R スタック操作。
\         STOR-TEST-TASK の実装 (kernel_forth_v0_8_5.fs L1298 等) と
\         パターン比較すること:
\           0 TEST-SRC-BUF 0 STOR-WRITE-OP STOR-DRV-TID @ IPC4-CALL
\         これは ( msg3=0  msg2=buf  msg1=lba  msg0=op  tid ) で TOS=tid
\         そのまま並べれば良い → 本実装の R スタック退避は過剰の可能性
: STOR-READ-1  ( lba buf -- r0 )
    SWAP                                     \ ( buf lba )
    STOR-READ-OP                             \ ( buf lba op )
    >R >R >R 0 R> R> R>                       \ ( 0 buf lba op )
    STOR-DRV-TID @                            \ ( 0 buf lba op tid )
    IPC4-CALL                                 \ ( r3 r2 r1 r0 )
    >R DROP DROP DROP R> ;                    \ r0 のみ残す

\ STOR-WRITE-1  ( lba buf -- r0 )                             ★REVIEW★
: STOR-WRITE-1  ( lba buf -- r0 )
    SWAP                                     \ ( buf lba )
    STOR-WRITE-OP                            \ ( buf lba op )
    >R >R >R 0 R> R> R>                       \ ( 0 buf lba op )
    STOR-DRV-TID @
    IPC4-CALL
    >R DROP DROP DROP R> ;

\ --------------------------------------------------------------------
\ スーパーブロック操作
\ --------------------------------------------------------------------

\ SB-LOAD  ( -- r0 )  LBA=0 を FS-SECBUF に読み込む
: SB-LOAD  ( -- r0 )
    0 FS-SECBUF STOR-READ-1 ;

\ SB-STORE  ( -- r0 )  FS-SECBUF を LBA=0 へ書き戻し
: SB-STORE  ( -- r0 )
    0 FS-SECBUF STOR-WRITE-1 ;

\ --------------------------------------------------------------------
\ ディレクトリ操作 (§5.6)
\ --------------------------------------------------------------------

\ DIR-LOAD  ( -- r0 )                                         ★REVIEW★
\ LBA 1,2,3 を FS-DIRBUF へ一括読み込み (3セクタ=1536B)
\ r0=0 成功、非0=どこかで STOR エラー
\ 検証点: 「最初のエラーコードだけ保持する」ロジックが正しいか
: DIR-LOAD  ( -- r0 )
    0 >R                                    \ R: i = 0
    0 FM-WK-C !                             \ FM-WK-C = 累計エラー = 0
    BEGIN  R@ FS-DIR-SECTORS <  WHILE
        FS-DIR-START R@ +                   \ LBA = 1 + i
        FS-DIRBUF R@ FS-SECSIZE * +         \ dst = FS-DIRBUF + i*512
        STOR-READ-1                         \ ( -- r0 )
        FM-WK-C @ 0= IF
            FM-WK-C !
        ELSE
            DROP
        THEN
        R> 1 + >R
    REPEAT
    R> DROP
    FM-WK-C @ ;

\ DIR-STORE  ( -- r0 )                                        ★REVIEW★
: DIR-STORE  ( -- r0 )
    0 >R
    0 FM-WK-C !
    BEGIN  R@ FS-DIR-SECTORS <  WHILE
        FS-DIR-START R@ +
        FS-DIRBUF R@ FS-SECSIZE * +
        STOR-WRITE-1
        FM-WK-C @ 0= IF
            FM-WK-C !
        ELSE
            DROP
        THEN
        R> 1 + >R
    REPEAT
    R> DROP
    FM-WK-C @ ;

\ DIR-FIND  ( name-addr -- index )                            ★REVIEW★
\ FS-DIRBUF から name 一致 & FLG_USED のエントリを探す。なければ -1
\ 前提  : DIR-LOAD 済み
\ 副作用: FM-WK-SRC/LEN/A/B/C/DST 破壊 (NAME-EQ? 経由)
: DIR-FIND  ( name-addr -- index )
    FM-WK-SRC !                              \ FM-WK-SRC = name-addr
    -1 FM-WK-LEN !                            \ 結果index, 初期 -1
    0 >R                                     \ R: i = 0
    BEGIN  R@ FS-DIR-ENTRIES <
           FM-WK-LEN @ -1 = AND               \ 未発見の間
    WHILE
        R@ DE-ADDR                           \ ( ent-addr )
        DUP DE-FLAGS + @ FLG-USED AND IF
            DUP                              \ ( ent ent )
            FM-WK-SRC @ SWAP NAME-EQ? IF
                R@ FM-WK-LEN !               \ index 確定
            THEN
        THEN
        DROP                                 \ ent 捨てる
        R> 1 + >R
    REPEAT
    R> DROP
    FM-WK-LEN @ ;

\ DIR-FIND-FREE  ( -- index )                                 ★REVIEW★
: DIR-FIND-FREE  ( -- index )
    -1 FM-WK-LEN !
    0 >R
    BEGIN  R@ FS-DIR-ENTRIES <
           FM-WK-LEN @ -1 = AND
    WHILE
        R@ DE-ADDR DE-FLAGS + @ FLG-USED AND 0= IF
            R@ FM-WK-LEN !                   \ 空きエントリ発見
        THEN
        R> 1 + >R
    REPEAT
    R> DROP
    FM-WK-LEN @ ;

\ --------------------------------------------------------------------
\ FS-MOUNT と FILEMGR-INIT (§5.4)
\ Forth は先方参照不可 → FS-MOUNT を先に定義
\ --------------------------------------------------------------------

\ FS-MOUNT  ( -- )                                            ★REVIEW★
\ LBA=0 を読み magic 検証 → 動的フィールドをキャッシュ
\ ver_major 不一致なら FS-MOUNTED=0 維持 (マウント拒否)
\ 副作用: FS-MOUNTED / FS-NEXT-FREE / FS-FILE-COUNT / FS-TOTAL-SEC / FS-FSVER 設定
\ 検証点: SB レイアウト (magic 8B, ver_major +8, ver_minor +9, total_sec +12,
\         next_free +24, file_count +26) が mkfs_yuifs.py の出力と一致するか
: FS-MOUNT  ( -- )
    SB-LOAD                                  \ FS-SECBUF に LBA=0 を読み込む
    0= INVERT IF
        EXIT                                 \ I/O エラー → 未マウント
    THEN
    FS-SECBUF MAGIC-CHECK 0= IF
        EXIT                                 \ magic 不一致 → 未マウント
    THEN
    \ version 読み出し (C@ 2回で明示 pack: major<<8 | minor、v1.2 review19)
    FS-SECBUF 8 + C@ 8 LSHIFT                \ major << 8
    FS-SECBUF 9 + C@ OR                       \ | minor
    FS-FSVER !
    \ ver_major 検査 (上位バイトが 1 でなければ拒否)
    FS-FSVER @ 8 RSHIFT $FF AND  1 = 0= IF
        EXIT                                 \ ver_major 不一致 → 未マウント
    THEN
    \ 動的フィールドをキャッシュ
    FS-SECBUF 12 + @ FS-TOTAL-SEC !          \ total_sectors
    FS-SECBUF 24 + @ FS-NEXT-FREE !          \ next_free_sec
    FS-SECBUF 26 + @ FS-FILE-COUNT !         \ file_count
    1 FS-MOUNTED ! ;

\ FILEMGR-INIT  ( -- )                                        ★REVIEW★
: FILEMGR-INIT  ( -- )
    FS-OPENTAB 0 64 MEMSET-B                 \ オープンテーブル 64B クリア
    0 FS-MOUNTED !
    0 FS-NEXT-FREE !
    0 FS-FILE-COUNT !
    0 FS-TOTAL-SEC !
    0 FS-WR-OLD-NEXT !
    0 FS-WR-OLD-COUNT !
    0 FS-FSVER !
    FS-MOUNT ;

\ --------------------------------------------------------------------
\ FILE-REORDER-MSG  ( msg3 msg2 msg1 msg0 -- arg2 arg1 arg0 op )
\ §5.7。msg と arg の対応が既に一致するため恒等。確定済み。
\ --------------------------------------------------------------------
: FILE-REORDER-MSG  ( msg3 msg2 msg1 msg0 -- arg2 arg1 arg0 op )
    ;                                         \ 恒等

\ --------------------------------------------------------------------
\ REPLY-OK  ( r0 tid -- )                                     ★REVIEW★
\ r0=値、r1=r2=r3=0 で IPC4-REPLY
\ 副作用: FM-WK-A/B 破壊
\ 検証点: VARIABLE 退避方式でスタック並びを確実に組み立てる
\ --------------------------------------------------------------------
: REPLY-OK  ( r0 tid -- )
    FM-WK-A !                                \ tid 退避
    FM-WK-B !                                \ r0 退避
    0 0 0 FM-WK-B @                          \ ( 0 0 0 r0 )
    FM-WK-A @ IPC4-REPLY ;

\ ====================================================================
\ ★★★ 以下、半製品 IMPL 群 (前チャットで未完成のまま中断) ★★★
\ ====================================================================
\ 注意: 以下の IMPL ワードは前チャットで初稿を書いたが、机上検証未了。
\       特に R スタック操作 (>R >R / R> R>) の depth と順序、VARIABLE の
\       使い回しに混乱の可能性あり。HANDOVER_CHAT27 §4 を確認し、必要に
\       応じて完全に書き直すこと。
\
\ 次回作業の推奨方針 (kaizen 原則1: 段階的進行):
\   Step A: ダミー FILEMGR-TASK で FILEMGR-START のビルド可能性を確認
\           (op を受信して E-OK を返すだけのスケルトン)
\   Step B: FS-MOUNT 単体動作確認 (mkfs_yuifs.py で SB を書いてから起動)
\   Step C: FILE-OPEN-IMPL → FILE-LIST-IMPL 等の読み取り系
\   Step D: FILE-WRITE-IMPL (ロールバック含む)
\   Step E: FILE-DELETE-IMPL
\   Step F: FILEMGR-TEST-TASK で ABCXD P Q 出力確認
\ ====================================================================

\ --------------------------------------------------------------------
\ FILE-OPEN-IMPL  ( arg2 arg1 arg0 tid -- )                   v0.10.4
\ §4.3.1 / §6.8 案I 確定版（設計書 yuios_ph4_filemgr_design_v1_6_1.md）
\
\ 入力:  arg0 = name_addr（NULL終端ファイル名）, arg1/arg2 = 予約(未検査), tid = client
\ 動作:  name を DIR-FIND → 空き OPENTAB スロット(最小index)を確保 →
\        DE 情報(dir_index/start_sec/size)をスロットへ記録 → fid を返す
\ 出力:  r0 = fid(0〜3) / E-NAMETOOLONG / E-IOERR(未マウント) / E-NOENT / E-MFILE
\
\ 副作用:
\   - FS-DIRBUF を読む（DIR-FIND 経由・変更なし）
\   - 成功時 FS-OPENTAB の1スロットを使用中へ（OT-USED/DIR-INDEX/START-SEC/SIZE/POS）
\   - DIR-FIND が FM-WK-SRC/LEN/A/B/C/DST を破壊、REPLY-OK が FM-WK-A/B を破壊
\
\ 危険な組合せ（KY19/v1.6.1・C2）:
\   - 見つけた fid・dir_index・走査カウンタ i は R スタック／データスタックで保持
\     （ワーク変数を流用しない）。走査ループ内で FM-WK 破壊ワードを呼ばない
\   - スロット各フィールド書き込みは ! = ( val addr -- ) の順序（値→アドレス→!）
\
\ 前提条件: FS-MOUNTED=1（FILEMGR-INIT 経由で DIR-LOAD 済み）
\ --------------------------------------------------------------------
: FILE-OPEN-IMPL  ( arg2 arg1 arg0 tid -- )
    \ [A] tid退避 + arg1/arg2破棄 + name_addr確保
    >R                              \ ( arg2 arg1 name_addr )  R: tid
    >R                              \ ( arg2 arg1 )            R: tid name_addr
    DROP DROP                       \ ( )                      R: tid name_addr
    R>                              \ ( name_addr )            R: tid

    \ [B] ガード1: name長チェック（15文字超=NAME-LEN>=16 で E-NAMETOOLONG）
    DUP NAME-LEN                    \ ( name_addr len )
    16 >= IF                        \ len >= 16 なら長すぎ
        DROP                        \ ( ) name_addr捨て
        E-NAMETOOLONG R> REPLY-OK EXIT
    THEN                            \ ( name_addr )

    \ [C] ガード2: マウントチェック
    FS-MOUNTED @ 0= IF
        DROP                        \ ( ) name_addr捨て
        E-IOERR R> REPLY-OK EXIT
    THEN                            \ ( name_addr )

    \ [D] DIR-FIND（FM-WK破壊するが以降FM-WK不使用）
    DIR-FIND                        \ ( di )  di=-1なら不在
    DUP -1 = IF
        DROP
        E-NOENT R> REPLY-OK EXIT
    THEN                            \ ( di )

    \ [E] di退避 → 空きスロット走査（found=-1初期、iはRスタック）
    >R                              \ ( )       R: tid di
    -1                              \ ( found )  found=-1
    0 >R                            \ ( found )  R: tid di i=0
    BEGIN  R@ FS-MAX-OPEN <
           OVER -1 = AND            \ i<4 かつ 未発見
    WHILE
        R@ SLOT-ADDR OT-USED + @ 0= IF   \ slot[i].used==0?
            DROP R@                 \ ( i )  found=i（古いfound捨て）
        THEN
        R> 1 + >R                   \ i++
    REPEAT
    R> DROP                         \ ( found )  i破棄  R: tid di

    \ [F] found==-1 なら E_MFILE
    DUP -1 = IF
        DROP                        \ ( )
        R> DROP                     \ di破棄  R: tid
        E-MFILE R> REPLY-OK EXIT
    THEN                            \ ( fid )  R: tid di（fid=found=0..3）

    \ [G] スロット記録（! = (val addr --) 順序、§6.6規約）
    1  OVER SLOT-ADDR OT-USED +  !          \ OT-USED = 1            ( fid )
    R@ OVER SLOT-ADDR OT-DIR-INDEX +  !     \ OT-DIR-INDEX = di      ( fid )
    R@ DE-ADDR DE-START-SEC + @             \ ( fid sval )
    OVER SLOT-ADDR OT-START-SEC +  !        \ OT-START-SEC = de+20   ( fid )
    R@ DE-ADDR DE-SIZE + @                  \ ( fid szval ) 下位16bit
    OVER SLOT-ADDR OT-SIZE +  !             \ OT-SIZE = de+16        ( fid )
    0  OVER SLOT-ADDR OT-POS +  !           \ OT-POS = 0             ( fid )

    \ [H] di破棄、fid返却
    R> DROP                         \ di破棄  R: tid  ( fid )
    R> REPLY-OK ;                   \ r0 = fid を REPLY

\ --------------------------------------------------------------------
\ FILE-CLOSE-IMPL  ( arg2 arg1 arg0 tid -- )                  v0.10.5
\ §4.3.2 / §6.9 確定版（設計書 yuios_ph4_filemgr_design_v1_6_1.md）
\
\ 入力:  arg0 = fid（OPEN が返した値）, arg1/arg2 = 予約(未検査), tid = client
\ 動作:  FID-VALID? で fid 検査 → 有効なら OT-USED を 0 に（使用中→未使用）
\ 出力:  r0 = E-OK(0) / E-BADF（範囲外 or 未オープン）
\
\ 副作用:
\   - 成功時 FS-OPENTAB の当該スロット OT-USED を 0 に（他フィールド不変）
\   - FS-DIRBUF / ディスクには一切触れない（RAM のみ操作・§4.3.2.4）
\   - REPLY-OK が FM-WK-A/B を破壊
\
\ 危険な組合せ（KY19）:
\   - fid は必ず FID-VALID? に通す（負値・範囲外・未used を一括判定。$FE0x を
\     fid として渡す事故も 0< 判定で弾く・§5.3.1）
\   - OT-USED 書き込みは ! = ( val addr -- ) 順序（値0先積み・アドレスTOS・§6.6）
\   - OT-USED の遷移点は OPEN(0→1)/CLOSE(1→0)の2箇所のみ（§5.3.2）
\
\ 前提条件: tid が有効なクライアント TCB（FS-MOUNTED は問わない・§4.3.2.4）
\ --------------------------------------------------------------------
: FILE-CLOSE-IMPL  ( arg2 arg1 arg0 tid -- )
    \ [A] tid退避 + arg1/arg2破棄 + fid確保（OPEN と同形）
    >R                              \ ( arg2 arg1 fid )  R: tid
    >R                              \ ( arg2 arg1 )      R: tid fid
    DROP DROP                       \ ( )                R: tid fid
    R>                              \ ( fid )            R: tid

    \ [B] fid検査（FID-VALID? 一本：負値・範囲外・未used を一括判定）
    DUP FID-VALID? 0= IF            \ ( fid )  無効なら
        DROP                        \ ( ) fid捨て
        E-BADF R> REPLY-OK EXIT
    THEN                            \ ( fid )  有効

    \ [C] OT-USED を 0 に（! = (val addr --) 順序、§6.6）
    0  SWAP                         \ ( 0 fid )
    SLOT-ADDR OT-USED +             \ ( 0 addr )  addr = fid*16 + base + OT-USED(=0)
    !                               \ ( )         OT-USED 1→0

    \ [D] 成功 REPLY: r0 = E-OK(0)
    0 R> REPLY-OK ;

\ --------------------------------------------------------------------
\ FILE-READ-IMPL  ( arg2 arg1 arg0 tid -- )                   v0.10.6
\ §4.3.3 / §6.3 / §6.3.1 確定版（設計書 yuios_ph4_filemgr_design_v1_7_1.md）
\
\ 入力:  arg0=fid, arg1=dst_addr, arg2=size, tid=client
\ 動作:  pos から min(size, fsz-pos) バイトを dst へ読む。pos を actual 進める。
\ 出力:  r0 = actual(0..$7FFF) / E-BADF / E-INVAL / E-IOERR
\
\ 異常系ガード順序（符号付き演算の正しさのため厳守・§4.3.3 手順・KY24）:
\   手順1 fid検査(FID-VALID?) → 手順2 size負ガード(0<) →
\   手順4 pos>=fsz ガード(actual=0) → 手順5 actual=MIN(size,fsz-pos)
\ 以降 MIN/比較を呼ぶ時点で全オペランド非負（手順2・4で保証）。
\
\ ループ変数は専用 VARIABLE FR-*（MEMCPY-B が壊す FM-WK と分離・§6.3.1 FM-WK
\ 非依存要件を VARIABLE 分離で満たす）。R スタックは tid 1 個で一貫保持。
\ STOR-READ-1 引数順 ( lba buf -- r0 ) 厳守。POS>LBA の sofs(TOS) 退避に注意（KY24）。
\ I/O エラー時は OT-POS 不変で E-IOERR（§6.3.1）。dst は部分書込みで不定（§4.3.3・C1）。
\
\ 前提条件: FS-MOUNTED=1（FILEMGR-INIT 経由で DIR-LOAD 済み）
\ --------------------------------------------------------------------
: FILE-READ-IMPL  ( arg2 arg1 arg0 tid -- )
    \ [A] tid退避 → ( size dst fid )  R: tid
    >R                              \ ( size dst fid )         R: tid

    \ [B] 手順1: fid検査（FID-VALID? 一本）
    DUP FID-VALID? 0= IF            \ ( size dst fid )  無効なら
        DROP DROP DROP              \ ( )
        E-BADF R> REPLY-OK EXIT
    THEN                            \ ( size dst fid )  有効

    \ [C] 手順2: size負ガード（案1：最上位bit=1＝$8000以上を弾く）
    \   size はスタック底（NOS の下）。ROT で TOS へ持ち上げて検査。
    ROT                             \ ( dst fid size )
    DUP 0< IF                       \ size<0（$8000以上）なら不正
        DROP DROP DROP              \ ( )
        E-INVAL R> REPLY-OK EXIT
    THEN                            \ ( dst fid size )  size>=0 確定

    \ size を FR-REMAIN へ仮置き（後で actual に縮める）
    FR-REMAIN !                     \ ( dst fid )   FR-REMAIN = size

    \ [D] 手順3: スロット値取得（fsz/pos/start）→ FR-* へ
    \   fid から SLOT-ADDR を一度だけ算出して FR-SLOT に保持（OT-POS 書戻し用・[H]）。
    SLOT-ADDR                       \ ( dst slot )  fid 消費→スロット先頭アドレス
    DUP FR-SLOT !                   \ ( dst slot )  FR-SLOT = slot（[H]で再利用）
    DUP OT-START-SEC + @  FR-START !  \ ( dst slot )  FR-START = start
    DUP OT-POS       + @  FR-POS   !  \ ( dst slot )  FR-POS   = pos
    OT-SIZE          + @            \ ( dst fsz )   slot 消費し fsz を得る
    SWAP FR-DST !                   \ ( fsz )       FR-DST = dst

    \ [E] 手順4: EOF先頭ガード pos>=fsz → actual=0
    \   ( fsz )  pos は FR-POS。pos>=fsz を判定。
    FR-POS @ OVER >= IF             \ ( fsz )  pos>=fsz なら
        DROP                        \ ( )
        0 R> REPLY-OK EXIT          \ actual=0
    THEN                            \ ( fsz )  pos<fsz 確定（fsz-pos>0）

    \ [F] 手順5: actual = MIN(size, fsz - pos)
    \   ( fsz )  残り = fsz - pos。size(=FR-REMAIN) と MIN。
    FR-POS @ -                      \ ( fsz-pos )  >0（[E]保証）
    FR-REMAIN @ MIN                 \ ( actual )   両値とも正→符号付きMIN安全
    DUP FR-ACTUAL !                 \ ( actual )   FR-ACTUAL = actual（戻り値保存）
    FR-REMAIN !                     \ ( )          FR-REMAIN = actual（ループ残量）
    \ ※size=0 のとき actual=0 → 下の WHILE が即偽でループ0回 → actual=0 返却

    \ [G] 手順6: セクタ跨ぎ転送ループ（状態は全て FR-*、R: tid のみ）
    BEGIN  FR-REMAIN @ 0>  WHILE
        \ pos→LBA/sofs（§6.10 純関数）
        FR-POS @ FR-START @ POS>LBA \ ( lba sofs )
        >R                          \ ( lba )           R: tid sofs
        \ 1セクタを FS-SECBUF へ読む（STOR-READ-1 引数順 lba buf）
        FS-SECBUF STOR-READ-1       \ ( r0 )            R: tid sofs
        \ I/O エラーチェック（非0なら OT-POS 不変で E-IOERR）
        0<> IF                      \ ( )               R: tid sofs
            R> DROP                 \ sofs 捨て          R: tid
            E-IOERR R> REPLY-OK EXIT \ OT-POS は未更新のまま
        THEN                        \ ( )               R: tid sofs
        R>                          \ ( sofs )          R: tid
        \ chunk = MIN(512 - sofs, remain)
        FS-SECSIZE OVER -           \ ( sofs 512-sofs )
        FR-REMAIN @ MIN             \ ( sofs chunk )     両値正→MIN安全
        \ MEMCPY-B( dst=FR-DST@, src=FS-SECBUF+sofs, len=chunk )
        \ ( sofs chunk ) → chunk を R 退避、src を作り、dst を底に積む
        >R                          \ ( sofs )           R: tid chunk
        FS-SECBUF +                 \ ( src=SECBUF+sofs )
        FR-DST @ SWAP               \ ( dst src )
        R@                          \ ( dst src chunk )  R: tid chunk
        MEMCPY-B                    \ ( )  dst[0..chunk-1]=src[..]（FM-WK破壊は許容）
        \ 状態前進: d+=chunk; pos+=chunk; remain-=chunk
        \ ※ +! (PLUS-STORE) は ysd8800.prim にバグ（val 無視で mem を2倍化）が
        \   あるため使用しない。@ + ! 等価形で実装する（Step 5-5 報告事項・KY24派生）。
        R>                          \ ( chunk )          R: tid
        FR-DST    @ OVER +  FR-DST    !   \ FR-DST    = FR-DST    + chunk
        FR-POS    @ OVER +  FR-POS    !   \ FR-POS    = FR-POS    + chunk
        FR-REMAIN @ SWAP -  FR-REMAIN !   \ FR-REMAIN = FR-REMAIN - chunk（chunk消費）
    REPEAT

    \ [H] 手順7: OT-POS ← pos（val addr ! 順序・§6.6 規約）→ actual を REPLY
    \   FR-SLOT に保持したスロット先頭から OT-POS フィールドへ最終 pos を書き戻す。
    FR-POS @                        \ ( pos )                 val
    FR-SLOT @ OT-POS +              \ ( pos addr )            addr = slot + OT-POS
    !                               \ ( )  OT-POS = pos（! = (val addr --)）
    FR-ACTUAL @ R> REPLY-OK ;       \ r0 = actual を REPLY（R から tid を戻して）


\ --------------------------------------------------------------------
\ FILE-WRITE-IMPL  ( arg2 arg1 arg0 tid -- )                  v0.10.7
\ §4.4 / §6.4 / §6.4.1.1 確定版（設計書 yuios_ph4_filemgr_design_v1_8_1.md）
\ Step 5-6a: 新規作成・単一セクタ(size<=512)・ロールバックなし・端数0パディング
\
\ 入力:  arg0=name_addr, arg1=src_addr, arg2=size, tid=client
\ 動作:  新規ファイル name を作成し src から size バイトを単一セクタへ書き込む。
\ 出力:  r0 = E-OK(0) / E-NAMETOOLONG / E-INVAL / E-IOERR / E-EXIST /
\              E-NODIRSPC / E-NOSPC
\
\ 書き込み順序厳守（§4.4.3・KY4）: データ[I] → ディレクトリ[K] → SB[M]
\ ★KY25: [I] でデータ用に潰した FS-SECBUF を [M] で必ず SB-LOAD で SB 内容へ
\        戻してから +24/+26 更新 → SB-STORE。怠るとデータが LBA0 を破壊する。
\ ループ変数・引数は専用 VARIABLE FW-*（FM-WK 非依存）。R は tid 1個で一貫。
\ 5-6a はロールバックなし（メモリ更新[L]はディスク書込[I][K]成功後＝[I][K]失敗時
\ メモリ未汚染。[M] SB-STORE 失敗時のみメモリが進んだ状態が残るが 5-6a は許容）。
\ --------------------------------------------------------------------
: FILE-WRITE-IMPL  ( arg2 arg1 arg0 tid -- )   \ arg0=name arg1=src arg2=size
    \ [A] tid退避 + 引数を FW-* へ退避 → データスタックを空にする
    >R                              \ ( size src name )       R: tid
    FW-NAME !                       \ ( size src )            FW-NAME = name
    FW-SRC !                        \ ( size )                FW-SRC  = src
    FW-SIZE !                       \ ( )                     FW-SIZE = size

    \ [B] 手順1: name 長検査（NAME-LEN >= 16 → E-NAMETOOLONG）
    FW-NAME @ NAME-LEN 15 > IF      \ len>15（=16頭打ち）なら名前長すぎ
        E-NAMETOOLONG R> REPLY-OK EXIT
    THEN

    \ [C] 手順2: size ガード（★5-6b: size>512 ガードは撤廃・負ガードのみ）
    FW-SIZE @ 0< IF                 \ 案1: 最上位bit=1（$8000以上）→不正
        E-INVAL R> REPLY-OK EXIT
    THEN
    \ ★5-6a の「FW-SIZE @ FS-SECSIZE > IF E-INVAL」は 5-6b で撤廃（複数セクタ許容）

    \ [C2] 手順5相当: 必要セクタ数 n を算出（§6.4.2.1・論点0=案A）
    \   n = ceil(size/512) = (size+511)>>9。ただし size==0 は n=1 特例
    \   （5-6a の C1: size=0 でも 512B 全0セクタを 1 つ書く挙動を維持）。
    \   Force に / mod 不在のため (size+511) 9 RSHIFT で算出（KY26 防止策⑤）。
    FW-SIZE @ 0= IF
        1 FW-N !                    \ size=0 特例: n=1
    ELSE
        FW-SIZE @ 511 + 9 RSHIFT FW-N !  \ n = ceil(size/512)
    THEN

    \ [D] 手順3: DIR-LOAD（§4.4.1 手順2 に従い再ロード）
    DIR-LOAD 0<> IF
        E-IOERR R> REPLY-OK EXIT
    THEN

    \ [E] 手順4: 同名チェック（DIR-FIND >= 0 → 既存 → E-EXIST）
    FW-NAME @ DIR-FIND 0< 0= IF     \ DIR-FIND >= 0（=見つかった）なら
        E-EXIST R> REPLY-OK EXIT
    THEN

    \ [F] 手順5: 空き DE 探索（DIR-FIND-FREE < 0 → E-NODIRSPC）
    DIR-FIND-FREE                   \ ( di )
    DUP 0< IF
        DROP E-NODIRSPC R> REPLY-OK EXIT
    THEN
    FW-DI !                         \ ( )  FW-DI = di（FM-WK 破壊前に退避・§6.4.1.4-3）

    \ [G] 手順6: 空き容量チェック（★5-6b 一般形: (next_free + n - 1) >= total）
    \   最終使用 LBA = next_free + n - 1。これが total 以上＝範囲外なら E-NOSPC。
    \   n=1 を代入すると 5-6a 式 next_free >= total に一致（KY26 防止策④・両値正で符号付き安全）。
    FS-NEXT-FREE @ FW-N @ + 1 - FS-TOTAL-SEC @ >= IF
        E-NOSPC R> REPLY-OK EXIT
    THEN

    \ [H] 手順7: start = FS-NEXT-FREE @
    FS-NEXT-FREE @ FW-START !        \ FW-START = start

    \ [I] 手順8-9: データ書き込み（★5-6b 複数セクタループ・書込順序の先頭）
    \   状態は全て FW-*（FM-WK 非依存・KY26 防止策①）。R は tid 1個で一貫。
    \   ループ条件は「書込済み < n」基準（remain 基準でない・size=0 で 0 セクタ回避・論点0）。
    \   ★v0.10.8c: 全セクタを SECBUF 経由で一律書込（chunk==512 の直接書込分岐を廃止）。
    \     READ のループと同型にし、ループ内の IF/ELSE 分岐を最小化（Force のループ内
    \     複雑分岐がスタック不整合を起こすため）。512B 丸ごとでも SECBUF にコピーして書く。
    \     chunk は FW-CHUNK 変数経由（値をスタックに残さない）。
    FW-START @ FW-LBA !             \ 書込先 LBA = start
    FW-SIZE  @ FW-REMAIN !          \ 残量 = size
    0          FW-WRITTEN !         \ 書込済みセクタ数 = 0
    BEGIN  FW-WRITTEN @ FW-N @ <  WHILE   \ n セクタ書くまで
        \ chunk = MIN(512, remain) → FW-CHUNK（remain>=512 なら 512、else remain）
        FW-REMAIN @ FS-SECSIZE >= IF
            FS-SECSIZE FW-CHUNK !      \ chunk=512（丸ごと）
        ELSE
            FW-REMAIN @ FW-CHUNK !     \ chunk=remain（端数 0..511・size=0 なら 0）
        THEN
        \ SECBUF を 0 クリアし、chunk バイトを src からコピー（一律 SECBUF 経由）
        FS-SECBUF 0 FS-SECSIZE MEMSET-B    \ SECBUF 全 512B を 0 クリア
        FW-CHUNK @ 0> IF                   \ chunk>0 のときだけコピー（len=0 暴走回避）
            FS-SECBUF FW-SRC @ FW-CHUNK @ MEMCPY-B   \ dst=SECBUF src=FW-SRC@ len=chunk
        THEN
        \ SECBUF を 1 セクタ書く（STOR-WRITE-1 は IF/ELSE の外で 1 回だけ呼ぶ＝READ同型）
        FW-LBA @ FS-SECBUF STOR-WRITE-1    \ ( r0 )
        0<> IF                             \ I/O エラー → E-IOERR（メモリ未更新・巻戻し不要）
            E-IOERR R> REPLY-OK EXIT
        THEN
        \ 3変数同期更新（ループ末尾1箇所に集約・順序固定・KY26 防止策③）
        FW-SRC    @ FS-SECSIZE +  FW-SRC    !   \ src += 512（最終端数周でも512進む=無害）
        FW-LBA    @ 1          +  FW-LBA    !   \ LBA += 1
        FW-REMAIN @ FS-SECSIZE -  FW-REMAIN !   \ remain -= 512（負可・WRITTEN<N基準で無影響）
        FW-WRITTEN @ 1        +  FW-WRITTEN !   \ 書込済み++
    REPEAT

    \ [J] 手順9-10: DE 書き込み（FS-DIRBUF 上・SECBUF 非依存）
    \   ent = FW-DI @ DE-ADDR。DE-ADDR は純関数のため毎回再計算してスタック錯綜を回避。
    \   各フィールドを ! = (val addr --) 順序（値を先に積みアドレスを TOS）で書く。
    \   - name（NUL込み16B・残り0埋め）
    FW-DI @ DE-ADDR DE-NAME +  FW-NAME @  NAME-COPY-16
                                    \ NAME-COPY-16(dst src): dst=ent+DE-NAME(NOS), src=name(TOS)
    \   - size 下位2B
    FW-SIZE @  FW-DI @ DE-ADDR DE-SIZE +  !
    \   - size 上位2B を明示0（★C3: DELETE 再利用時の残骸事故防止）
    0  FW-DI @ DE-ADDR DE-SIZE + 2 +  !
    \   - start_sec
    FW-START @  FW-DI @ DE-ADDR DE-START-SEC +  !
    \   - sec_count = FW-N（★5-6b: 確保セクタ数 n。5-6a は 1 固定だった）
    FW-N @  FW-DI @ DE-ADDR DE-SEC-COUNT +  !
    \   - flags = FLG-USED
    FLG-USED  FW-DI @ DE-ADDR DE-FLAGS +  !

    \ [K] 手順11: ディレクトリ書き戻し
    DIR-STORE 0<> IF
        E-IOERR R> REPLY-OK EXIT     \ メモリ未更新（[L]未実施）・巻戻し不要
    THEN

    \ [L'] 手順7: ロールバック退避（★5-6c: メモリ更新[L]の直前に固定・KY26）
    \   退避値 = 更新前の旧値。[M] SB-LOAD/SB-STORE 失敗時にこれを書き戻す。
    FS-NEXT-FREE  @  FS-WR-OLD-NEXT  !
    FS-FILE-COUNT @  FS-WR-OLD-COUNT !

    \ [L] 手順12: メモリ確定更新（ディスク書込[I][K]成功後・+! は prim v1.1 修正済み）
    FW-N @ FS-NEXT-FREE +!          \ ★5-6b: FS-NEXT-FREE += n（5-6a は +1）
    1 FS-FILE-COUNT +!              \ FS-FILE-COUNT += 1（ファイル数は1増）

    \ [M] 手順13: SB 書き戻し（★KY25: SECBUF 二重用途）
    \   [I] でデータ用に潰した可能性のある SECBUF を SB-LOAD で SB 内容へ戻してから
    \   +24/+26 を更新し SB-STORE する。SB-LOAD は [I] の枝に依らず常に実行（C2）。
    SB-LOAD 0<> IF
        \ ★5-6c: SB-LOAD 失敗も巻戻し対象（論点①）。メモリのみ巻戻し（論点③）
        FS-WR-OLD-NEXT  @  FS-NEXT-FREE  !
        FS-WR-OLD-COUNT @  FS-FILE-COUNT !
        E-IOERR R> REPLY-OK EXIT     \ SB-LOAD 失敗
    THEN
    FS-NEXT-FREE @   FS-SECBUF 24 +  !   \ SECBUF+24 = next_free_sec
    FS-FILE-COUNT @  FS-SECBUF 26 +  !   \ SECBUF+26 = file_count
    SB-STORE 0<> IF
        \ ★5-6c: SB-STORE 失敗で巻戻し（論点①）。メモリのみ巻戻し（論点③）
        FS-WR-OLD-NEXT  @  FS-NEXT-FREE  !
        FS-WR-OLD-COUNT @  FS-FILE-COUNT !
        E-IOERR R> REPLY-OK EXIT     \ SB-STORE 失敗
    THEN

    \ [N] 手順14: 成功 REPLY（r0 = E-OK）
    0 R> REPLY-OK ;

\ ★TODO★ FILE-SEEK-IMPL  ( arg2 arg1 arg0 tid -- )  §4.3.4

\ --------------------------------------------------------------------
\ FILE-STAT-IMPL  ( arg2 arg1 arg0 tid -- )                   v0.10.2a 定義のみ
\ §4.3.5 FILE_STAT (0x0206)
\   入力 (底→TOS): arg2=0(未使用), arg1=stat_buf, arg0=name_addr, tid=client_tid
\   stat_buf 構造 (16B):
\     +0 size(4B)  +4 start_sec(2B)  +6 sec_count(2B)
\     +8 flags(2B) +10 予約(6B、0埋め)
\   戻り: r0 = E-OK(0) / E-NOENT / E-IOERR
\ 副作用: FM-WK-DST/SRC/LEN/VAL/A/B/C 破壊 (DIR-FIND, MEMCPY-B, MEMSET-B, REPLY-OK 経由)
\ 前提  : FILEMGR-INIT で FS-MOUNT + DIR-LOAD 済み (FS-DIRBUF が最新であること)
\
\ v0.10.2a メモ: 本ワードは定義のみ (FILEMGR-TASK からは呼ばれない)。
\                仮説γ (コードの存在自体がレイアウト破壊する) の切り分けが目的。
\ --------------------------------------------------------------------
: FILE-STAT-IMPL  ( arg2 arg1 arg0 tid -- )
    >R                              \ R: tid

    \ FS-MOUNTED チェック
    FS-MOUNTED @ 0= IF
        DROP DROP DROP
        E-IOERR R> REPLY-OK EXIT
    THEN

    \ arg2(=0) を捨て ( stat_buf name_addr ) にする
    ROT DROP                        \ ( stat_buf name_addr )

    \ DIR-FIND を呼ぶ。stat_buf を R スタックへ退避 (FM-WK 破壊から守る)
    SWAP >R                         \ R: tid stat_buf, stack: ( name_addr )
    DIR-FIND                        \ ( -- index )
    R>                              \ ( index stat_buf ), R: tid
    SWAP                            \ ( stat_buf index )

    \ index = -1 なら NOENT
    DUP -1 = IF
        DROP
        DROP
        E-NOENT R> REPLY-OK EXIT
    THEN

    \ de_addr 計算
    DE-ADDR                         \ ( stat_buf de_addr )

    \ MEMCPY-B ( dst src len -- ) で de_addr+16 から stat_buf+0 へ 10B
    16 +                            \ ( stat_buf src )
    OVER                            \ ( stat_buf src stat_buf )
    SWAP                            \ ( stat_buf stat_buf src )
    10                              \ ( stat_buf stat_buf src 10 )
    MEMCPY-B                        \ ( stat_buf )

    \ MEMSET-B ( dst val len -- ) で stat_buf+10 から 6B を 0 埋め
    10 +                            \ ( stat_buf+10 )
    0                               \ ( stat_buf+10 0 )
    6                               \ ( stat_buf+10 0 6 )
    MEMSET-B                        \ ( -- )

    \ 成功 REPLY: r0 = 0
    0 R> REPLY-OK ;

\ --------------------------------------------------------------------
\ FILE-DISPATCH-STAT  ( arg2 arg1 arg0 op tid -- )            v0.10.2a 定義のみ
\ Step 5-1 暫定ディスパッチ: FILE-STAT-OP のみ処理、他は E-INVAL。
\ v0.10.2a メモ: 本ワードも定義のみ (FILEMGR-TASK からは呼ばれない)。
\ v0.10.3 メモ: 後続 FILE-DISPATCH に統合済み。後方互換のため定義は残置。
\ --------------------------------------------------------------------
: FILE-DISPATCH-STAT  ( arg2 arg1 arg0 op tid -- )
    >R                              \ R: tid
    DUP FILE-STAT-OP = IF
        DROP R> FILE-STAT-IMPL EXIT
    THEN
    DROP DROP DROP DROP
    E-INVAL R> REPLY-OK ;

\ --------------------------------------------------------------------
\ FILE-LIST-IMPL  ( arg2 arg1 arg0 tid -- )                   v0.10.3
\ §4.3.6 / §6.7.3 案I 確定版（設計書 yuios_ph4_filemgr_design_v1_5_2.md）
\
\ 入力:  arg0 = buf_addr, arg1 = buf_size, arg2 = 予約(必ず0), tid = client
\ 動作:  FS-DIRBUF を走査し、FLG_USED=1 の name (16B) を buf_addr に連続書込
\ 出力:  r0 = 書き込み済みエントリ数 / E-IOERR (FS未マウント) / E-INVAL (arg2≠0)
\
\ 副作用:
\   - 使用ワーク変数: FM-WK-COUNT/REMAIN/PTR（案P、MEMCPY-B 衝突回避）
\   - 走査インデックス i は R スタック保持
\   - FS-DIRBUF を読むのみ（変更しない）
\   - buf_addr へ最大 16 × FS-DIR-ENTRIES バイト書込
\
\ 危険な組合せ:
\   - カウンタ/ポインタに FM-WK-LEN/SRC/DST/VAL を使わない
\     （MEMCPY-B/MEMSET-B が破壊するため）
\
\ 前提条件:
\   - FS-MOUNTED が 1（FILEMGR-INIT 経由で DIR-LOAD 済み）
\   - tid が有効なクライアント TCB（IPC4 ランタイムが保証）
\ --------------------------------------------------------------------
: FILE-LIST-IMPL  ( arg2 arg1 arg0 tid -- )
    >R                                  \ R: tid
    \ --- ガード1: FS-MOUNTED チェック ---
    FS-MOUNTED @ 0= IF
        DROP DROP DROP                  \ arg0/arg1/arg2 を捨てる
        E-IOERR R> REPLY-OK EXIT
    THEN
    \ --- ガード2: arg2 ≠ 0 チェック（予約値域）---
    ROT DUP IF                          \ ( arg1 arg0 arg2 ), arg2 を検査
        DROP DROP DROP
        E-INVAL R> REPLY-OK EXIT
    THEN
    DROP                                \ arg2(=0) 捨てる ( arg1 arg0 )
    \ 残: ( buf_size buf_addr ) TOS=buf_addr
    SWAP                                \ ( buf_addr buf_size )
    \ --- max_n = buf_size / 16 を計算（SLASH 未対応のため 4 RSHIFT）---
    4 RSHIFT                            \ ( buf_addr max_n )
    FM-WK-REMAIN !                      \ FM-WK-REMAIN = max_n
    FM-WK-PTR !                         \ FM-WK-PTR = buf_addr
    0 FM-WK-COUNT !                     \ FM-WK-COUNT = 0

    0 >R                                \ R: tid i=0
    \ --- メインループ: i < FS-DIR-ENTRIES かつ 残枠 > 0 の間 ---
    BEGIN  R@ FS-DIR-ENTRIES <
           FM-WK-REMAIN @ 0 > AND
    WHILE
        R@ DE-ADDR                      \ ( de_addr )  DE-ADDR §6.6
        DUP DE-FLAGS + @ FLG-USED AND IF \ ( de_addr ) USED 判定
            \ --- USED: name 16B を FM-WK-PTR へコピー ---
            FM-WK-PTR @                 \ ( de_addr dst )
            OVER DE-NAME +              \ ( de_addr dst src )  src = de_addr+0
            16 MEMCPY-B                 \ ( de_addr )  16B コピー実行
            \ --- ポインタ・カウンタ更新（専用変数のみ操作）---
            FM-WK-PTR @ 16 + FM-WK-PTR !
            FM-WK-COUNT @ 1 + FM-WK-COUNT !
            FM-WK-REMAIN @ 1 - FM-WK-REMAIN !
        THEN
        DROP                            \ de_addr 捨てる
        R> 1 + >R                       \ i++
    REPEAT
    R> DROP                             \ i 捨てる

    \ --- 成功 REPLY: r0 = 書き込み済み件数 ---
    FM-WK-COUNT @ R> REPLY-OK ;

\ ★TODO★ FILE-DELETE-IMPL  ( arg2 arg1 arg0 tid -- )  §4.3.7

\ --------------------------------------------------------------------
\ FILE-DISPATCH  ( arg2 arg1 arg0 op tid -- )                 v0.10.5
\ §6.1 op で IMPL に分岐。Step 5-2 LIST、5-3 OPEN、5-4 CLOSE を追加。
\ MEMMGR-DISPATCH を雛形にする。
\
\ サポート op:
\   FILE-OPEN-OP  ($0201): FILE-OPEN-IMPL へ（v0.10.4）
\   FILE-CLOSE-OP ($0202): FILE-CLOSE-IMPL へ（v0.10.5）
\   FILE-STAT-OP  ($0206): FILE-STAT-IMPL へ
\   FILE-LIST-OP  ($0207): FILE-LIST-IMPL へ
\   その他       : E-INVAL を REPLY
\ --------------------------------------------------------------------
: FILE-DISPATCH  ( arg2 arg1 arg0 op tid -- )
    >R                                  \ R: tid
    DUP FILE-OPEN-OP = IF
        DROP R> FILE-OPEN-IMPL EXIT     \ FILE-OPEN-IMPL は ( arg2 arg1 arg0 tid -- )
    THEN
    DUP FILE-CLOSE-OP = IF
        DROP R> FILE-CLOSE-IMPL EXIT    \ FILE-CLOSE-IMPL は ( arg2 arg1 arg0 tid -- )
    THEN
    DUP FILE-STAT-OP = IF
        DROP R> FILE-STAT-IMPL EXIT     \ FILE-STAT-IMPL は ( arg2 arg1 arg0 tid -- )
    THEN
    DUP FILE-LIST-OP = IF
        DROP R> FILE-LIST-IMPL EXIT     \ FILE-LIST-IMPL は ( arg2 arg1 arg0 tid -- )
    THEN
    DUP FILE-READ-OP = IF
        DROP R> FILE-READ-IMPL EXIT     \ ★v0.10.6: FILE-READ-IMPL ( arg2 arg1 arg0 tid -- )
    THEN
    DUP FILE-WRITE-OP = IF
        DROP R> FILE-WRITE-IMPL EXIT    \ ★v0.10.7: FILE-WRITE-IMPL ( arg2 arg1 arg0 tid -- )
    THEN
    DROP DROP DROP DROP                 \ arg0/arg1/arg2/op 捨てる
    E-INVAL R> REPLY-OK ;

\ ====================================================================
\ v0.10.0 (Step 4): FILEMGR-TASK / FILEMGR-START 最小実装
\ ====================================================================
\ Step 4 の目的は FS-MOUNT 単体動作確認のみ。FILE-DISPATCH は Step 5 で実装。
\ 本版では IPC4-RECV で受信したメッセージは黙って捨てて次の RECV に戻る。
\ 将来の追加実装に備えて IPC4-RECV → IPC4-SENDER-DIRECT → AGAIN のループは
\ STOR-DRV-TASK と同形にしておく (Step 5 で FILE-DISPATCH を挿入する位置を
\ 明確化)。

\ --------------------------------------------------------------------
\ FILEMGR-PUTC  ( char -- )                                  v0.10.0
\ char を UART へ 1文字出力 (デバッグ用ヘルパ)
\ 副作用: IPC4-CALL の戻り値 4ワード DROP
\ --------------------------------------------------------------------
: FILEMGR-PUTC  ( char -- )
    \ ( char ) → ( 0 0 char op tid ) [底→TOS]
    >R                                  \ R:(char) DSP:()
    0 0                                 \ DSP:(0 0) = (msg3 msg2)
    R>                                  \ DSP:(0 0 char) = (msg3 msg2 msg1)
    UART-PUTC-OP                        \ DSP:(0 0 char op) = (msg3 msg2 msg1 msg0)
    UART-DRV-TID @                      \ DSP:(0 0 char op tid)
    IPC4-CALL
    DROP DROP DROP DROP ;

\ --------------------------------------------------------------------
\ FS-MOUNT-DBG  ( -- )                                       v0.10.0
\ FS-MOUNT のデバッグ版。各段階で識別文字を出力する。
\   '0' : SB-LOAD 開始前
\   'i' : SB-LOAD I/O エラー (r0 != 0)
\   '1' : SB-LOAD 成功、MAGIC-CHECK 開始前
\   'g' : MAGIC-CHECK 不一致
\   '2' : MAGIC 一致、version 読出開始
\   'v' : ver_major 不一致
\   '3' : ver_major OK、キャッシュ書込開始
\   'M' : FS-MOUNTED=1 で完了
\ --------------------------------------------------------------------
: FS-MOUNT-DBG  ( -- )
    $30 FILEMGR-PUTC                    \ '0' SB-LOAD 開始
    SB-LOAD
    DUP 0= INVERT IF
        DROP $69 FILEMGR-PUTC           \ 'i' I/O エラー
        EXIT
    THEN
    DROP                                \ r0 (=0) 捨て
    $31 FILEMGR-PUTC                    \ '1' SB-LOAD 成功
    FS-SECBUF MAGIC-CHECK 0= IF
        $67 FILEMGR-PUTC                \ 'g' magic 不一致
        EXIT
    THEN
    $32 FILEMGR-PUTC                    \ '2' magic OK
    FS-SECBUF 8 + C@ 8 LSHIFT
    FS-SECBUF 9 + C@ OR
    FS-FSVER !
    FS-FSVER @ 8 RSHIFT $FF AND 1 = 0= IF
        $76 FILEMGR-PUTC                \ 'v' ver_major 不一致
        EXIT
    THEN
    $33 FILEMGR-PUTC                    \ '3' ver_major OK
    FS-SECBUF 12 + @ FS-TOTAL-SEC !
    FS-SECBUF 24 + @ FS-NEXT-FREE !
    FS-SECBUF 26 + @ FS-FILE-COUNT !
    1 FS-MOUNTED !
    $4D FILEMGR-PUTC ;                  \ 'M' 完了

\ --------------------------------------------------------------------
\ FILEMGR-INIT-DBG  ( -- )                                   v0.10.0
\ FILEMGR-INIT のデバッグ版。FS-MOUNT-DBG を呼ぶ。
\ --------------------------------------------------------------------
: FILEMGR-INIT-DBG  ( -- )
    FS-OPENTAB 0 64 MEMSET-B
    0 FS-MOUNTED !
    0 FS-NEXT-FREE !
    0 FS-FILE-COUNT !
    0 FS-TOTAL-SEC !
    0 FS-WR-OLD-NEXT !
    0 FS-WR-OLD-COUNT !
    0 FS-FSVER !
    FS-MOUNT-DBG
    \ v0.10.2i: DIR-LOAD を追加して FS-DIRBUF を初期化
    \ (STAT-IMPL → DIR-FIND の前提「DIR-LOAD 済み」を満たす)
    DIR-LOAD DROP                       \ エラー無視 (デバッグ用、後で本番化)
    $44 FILEMGR-PUTC ;                  \ 'D' = DIR-LOAD 完了

\ --------------------------------------------------------------------
\ FILEMGR-PUTC-M  ( -- )                                     v0.10.0
\ FS-MOUNTED の値に応じて 'M' (成功) または 'm' (失敗) を UART 出力
\ 副作用: DSP 上に IPC4-CALL の戻り値が残らないよう DROP DROP DROP DROP で清掃
\ --------------------------------------------------------------------
: FILEMGR-PUTC-M  ( -- )
    FS-MOUNTED @ IF
        0 0 $4D UART-PUTC-OP UART-DRV-TID @ IPC4-CALL    \ 'M' (=$4D)
    ELSE
        0 0 $6D UART-PUTC-OP UART-DRV-TID @ IPC4-CALL    \ 'm' (=$6D)
    THEN
    DROP DROP DROP DROP ;

\ --------------------------------------------------------------------
\ FILEMGR-TASK  ( -- )                                       v0.10.2b 拡張
\ FileMgr メインタスク (tid=4)。STOR-DRV-TASK と同形のサーバループ。
\ v0.10.0: FILEMGR-INIT-DBG → IPC4-RECV AGAIN (メッセージ捨て)
\ v0.10.2b: IPC4-RECV → DI → SENDER-DIRECT → EI → REORDER-MSG → FILE-DISPATCH-STAT
\ v0.10.3 (Step 5-2): FILE-DISPATCH-STAT → FILE-DISPATCH（FILE-LIST-OP 追加）
\ --------------------------------------------------------------------
: FILEMGR-TASK  ( -- )
    FILEMGR-INIT-DBG                    \ デバッグ版 (段階ごとに文字出力)
    BEGIN
        IPC4-RECV                       \ ( -- msg3 msg2 msg1 msg0 )
        DI-OP
        IPC4-SENDER-DIRECT >R           \ R: client_tid
        EI-OP
        FILE-REORDER-MSG                \ ( -- arg2 arg1 arg0 op ) 恒等
        R>                              \ ( -- arg2 arg1 arg0 op tid )
        FILE-DISPATCH                   \ v0.10.3: STAT + LIST dispatch
    AGAIN ;

\ --------------------------------------------------------------------
\ FILEMGR-TASK-ADDR  ( -- addr )                             v0.10.0
\ FILEMGR-TASK の Forth ワード先頭アドレスを DSP に積む
\ TASK-CREATE に渡すために必要 (STOR-DRV-TASK-ADDR と同形)
\ --------------------------------------------------------------------
CODE FILEMGR-TASK-ADDR  ( -- addr )
    SUBI X, #2
    LDW  A, #WORD_FILEMGR_TASK
    STW  A, [X]
END-CODE

\ --------------------------------------------------------------------
\ FILEMGR-START  ( -- )                                      v0.10.0
\ FileMgr タスクを生成し、tid を FILEMGR-TID-ADDR に格納
\ STOR-START の後・テストタスク起動の前に呼ぶこと
\ --------------------------------------------------------------------
: FILEMGR-START  ( -- )
    FILEMGR-TASK-ADDR TASK-CREATE       \ ( -- tid )
    FILEMGR-TID-ADDR ! ;                \ tid を $4800 へ格納

\ ★TODO★ FILEMGR-TEST-TASK  ( -- )
\         §8.3 テストシナリオ実装。期待出力: ABCXD P Q

\ ★TODO★ FILEMGR-TEST-START  ( -- )

\ --------------------------------------------------------------------
\ FILEMGR-TEST-TASK  ( -- )                                   v0.10.3
\ v0.10.2d: 仮説ε検証用。FILE_STAT を即送信→'Q' 出力
\ v0.10.3 (Step 5-2): FILE_STAT 後に FILE-LIST-TEST を追加
\   - 試験 buf = TEST-DST-BUF + $100（=$EF00, 256B）
\     ※設計書 v1.5.2 §8.4.3.1 訂正後（旧 v1.5/v1.5.1 の $F900 はタスクスタック衝突）
\   - 期待 r0=1（mkfs が hello.txt 1個を作成）→ 'L' 出力
\   - r0≠1 なら 'l'（小文字）出力で識別
\ バッファは TEST-SRC-BUF/DST-BUF と衝突しないように +$80 / +$100 オフセット使用。
\ --------------------------------------------------------------------
: FILEMGR-TEST-TASK  ( -- )
    \ "no.txt\0" を TEST-SRC-BUF+$80 へ ($EC80, S5 後でも安全)
    $6E TEST-SRC-BUF $80 +     C!
    $6F TEST-SRC-BUF $80 + 1 + C!
    $2E TEST-SRC-BUF $80 + 2 + C!
    $74 TEST-SRC-BUF $80 + 3 + C!
    $78 TEST-SRC-BUF $80 + 4 + C!
    $74 TEST-SRC-BUF $80 + 5 + C!
    $00 TEST-SRC-BUF $80 + 6 + C!

    \ FILE_STAT 送信
    0 TEST-DST-BUF $80 + TEST-SRC-BUF $80 + FILE-STAT-OP FILEMGR-TID-ADDR @ IPC4-CALL
    >R DROP DROP DROP R>

    E-NOENT = IF
        $51 FILEMGR-PUTC                \ 'Q' (FILEMGR-PUTC 使用、オリジナルv0.10.2 と同形)
    ELSE
        $71 FILEMGR-PUTC                \ 'q'
    THEN

    \ v0.10.3 (Step 5-2): FILE-LIST-TEST
    \   IPC4-CALL ( msg3 msg2 msg1 msg0 tid -- r0 r1 r2 r3 )
    \   FILE_LIST: msg3=0, msg2=buf_size, msg1=buf_addr, msg0=op
    0                                       \ msg3 = arg2 = 0 (予約)
    $100                                    \ msg2 = arg1 = buf_size = 256
    TEST-DST-BUF $100 +                     \ msg1 = arg0 = buf_addr = $EF00
    FILE-LIST-OP                            \ msg0 = $0207
    FILEMGR-TID-ADDR @                      \ tid = FILEMGR-TID
    IPC4-CALL                               \ ( -- r0 r1 r2 r3 ), r0 = エントリ数
    >R DROP DROP DROP R>                    \ r1/r2/r3 を捨てて r0 のみ残す

    1 = IF
        $4C FILEMGR-PUTC                \ 'L' (FILE-LIST-IMPL 完了)
    ELSE
        $6C FILEMGR-PUTC                \ 'l' (失敗)
    THEN

    \ v0.10.4 (Step 5-3): FILE-OPEN-TEST
    \   設計書 v1.6.1 §8.4.4.2。"hello.txt"(mkfs --add-file で作成)を OPEN。
    \   最小空きindex方式(§5.3.3)により最初の OPEN は必ず fid=0 → r0=0 なら 'O'
    \   "hello.txt\0" を TEST-SRC-BUF+$A0 へ ($ECA0, 他テストバッファと非衝突)
    $68 TEST-SRC-BUF $A0 +     C!       \ 'h'
    $65 TEST-SRC-BUF $A0 + 1 + C!       \ 'e'
    $6C TEST-SRC-BUF $A0 + 2 + C!       \ 'l'
    $6C TEST-SRC-BUF $A0 + 3 + C!       \ 'l'
    $6F TEST-SRC-BUF $A0 + 4 + C!       \ 'o'
    $2E TEST-SRC-BUF $A0 + 5 + C!       \ '.'
    $74 TEST-SRC-BUF $A0 + 6 + C!       \ 't'
    $78 TEST-SRC-BUF $A0 + 7 + C!       \ 'x'
    $74 TEST-SRC-BUF $A0 + 8 + C!       \ 't'
    $00 TEST-SRC-BUF $A0 + 9 + C!       \ NUL

    \ FILE_OPEN 送信: msg3=arg2=0, msg2=arg1=0, msg1=arg0=name_addr, msg0=op
    0                                       \ msg3 = arg2 = 0
    0                                       \ msg2 = arg1 = 0
    TEST-SRC-BUF $A0 +                      \ msg1 = arg0 = name_addr
    FILE-OPEN-OP                            \ msg0 = $0201
    FILEMGR-TID-ADDR @                      \ tid
    IPC4-CALL                               \ ( -- r0 r1 r2 r3 ), r0 = fid or error
    >R DROP DROP DROP R>                    \ r1/r2/r3 を捨てて r0 のみ残す

    DUP FT-FID !                            \ ★v0.10.5: fid を CLOSE 用に保存
    0 = IF
        $4F FILEMGR-PUTC                \ 'O' (fid=0 で OPEN 成功)
    ELSE
        $6F FILEMGR-PUTC                \ 'o' (失敗 or fid≠0)
    THEN

    \ v0.10.6 (Step 5-5): FILE-READ-TEST
    \   設計書 v1.7.1 §8.4.5.3。O1 で得た fid(=FT-FID) に対し size=16 で READ。
    \   hello.txt の中身 "Hello, YUI OS!\n"(15B・mkfs --add-file が改行込み15B書込)を
    \   FT-DST-BUF へ読む。期待 r0=15（actual。size=16>残り15 で部分読み・EOF）かつ
    \   FT-DST-BUF[0]=='H'。★設計書 §8.4.5.3 は「14B」想定だったが mkfs_yuifs_v1_1.py
    \   の実装は 'Hello, YUI OS!\n'=15B（改行込み）であり、実態に合わせ 15 で検証する
    \   （設計書改版で §8.4.5.3 を 15B へ訂正予定・Step 5-5 報告事項）。
    \   ★OPEN→READ→CLOSE の順（CLOSE 後の fid で READ すると E-BADF になるため）。
    \   FILE_READ: msg3=arg2=size, msg2=arg1=dst, msg1=arg0=fid, msg0=op
    16                                      \ msg3 = arg2 = size = 16
    FT-DST-BUF                              \ msg2 = arg1 = dst = $EE00
    FT-FID @                                \ msg1 = arg0 = fid（OPEN で得た値）
    FILE-READ-OP                            \ msg0 = $0203
    FILEMGR-TID-ADDR @                      \ tid
    IPC4-CALL                               \ ( -- r0 r1 r2 r3 ), r0 = actual / err
    >R DROP DROP DROP R>                    \ r1/r2/r3 を捨てて r0 のみ残す

    \ 検証: r0==15 かつ FT-DST-BUF[0]=='H'($48) なら 'R'、それ以外は 'r'
    15 = IF
        FT-DST-BUF C@ $48 = IF
            $52 FILEMGR-PUTC            \ 'R' (READ 成功・actual=15・先頭'H')
        ELSE
            $72 FILEMGR-PUTC            \ 'r' (actual=15 だが先頭≠'H'＝コピー異常)
        THEN
    ELSE
        $72 FILEMGR-PUTC                \ 'r' (actual≠15)
    THEN

    \ v0.10.5 (Step 5-4): FILE-CLOSE-TEST
    \   設計書 v1.6.1 §8.4.4.3。O1 で得た fid(=FT-FID) を CLOSE。
    \   FILE_CLOSE: msg3=0, msg2=0, msg1=fid, msg0=op
    0                                       \ msg3 = arg2 = 0
    0                                       \ msg2 = arg1 = 0
    FT-FID @                                \ msg1 = arg0 = fid（OPEN で得た値）
    FILE-CLOSE-OP                           \ msg0 = $0202
    FILEMGR-TID-ADDR @                      \ tid
    IPC4-CALL                               \ ( -- r0 r1 r2 r3 ), r0 = E-OK / E-BADF
    >R DROP DROP DROP R>                    \ r1/r2/r3 を捨てて r0 のみ残す

    0 = IF
        $43 FILEMGR-PUTC                \ 'C' (CLOSE 成功)
    ELSE
        $63 FILEMGR-PUTC                \ 'c' (失敗)
    THEN

    \ v0.10.7 (Step 5-6a): FILE-WRITE-TEST
    \   設計書 v1.8.1 §8.4.6.2。新規ファイル "wtest.txt" を size=6 "WRITE!" で WRITE。
    \   r0=0(E-OK) なら 'W'、それ以外 'w'。期待出力 …QLORCW。
    \   name "wtest.txt\0"(10B) を TEST-SRC-BUF+$C0 ($ECC0)、
    \   src  "WRITE!"(6B)       を TEST-SRC-BUF+$E0 ($ECE0) へ用意（他テストと非衝突）。
    $77 TEST-SRC-BUF $C0 +     C!       \ 'w'
    $74 TEST-SRC-BUF $C0 + 1 + C!       \ 't'
    $65 TEST-SRC-BUF $C0 + 2 + C!       \ 'e'
    $73 TEST-SRC-BUF $C0 + 3 + C!       \ 's'
    $74 TEST-SRC-BUF $C0 + 4 + C!       \ 't'
    $2E TEST-SRC-BUF $C0 + 5 + C!       \ '.'
    $74 TEST-SRC-BUF $C0 + 6 + C!       \ 't'
    $78 TEST-SRC-BUF $C0 + 7 + C!       \ 'x'
    $74 TEST-SRC-BUF $C0 + 8 + C!       \ 't'
    $00 TEST-SRC-BUF $C0 + 9 + C!       \ NUL
    $57 TEST-SRC-BUF $E0 +     C!       \ 'W'
    $52 TEST-SRC-BUF $E0 + 1 + C!       \ 'R'
    $49 TEST-SRC-BUF $E0 + 2 + C!       \ 'I'
    $54 TEST-SRC-BUF $E0 + 3 + C!       \ 'T'
    $45 TEST-SRC-BUF $E0 + 4 + C!       \ 'E'
    $21 TEST-SRC-BUF $E0 + 5 + C!       \ '!'

    \ FILE_WRITE: msg3=arg2=size, msg2=arg1=src, msg1=arg0=name, msg0=op
    6                                       \ msg3 = arg2 = size = 6
    TEST-SRC-BUF $E0 +                      \ msg2 = arg1 = src
    TEST-SRC-BUF $C0 +                      \ msg1 = arg0 = name
    FILE-WRITE-OP                           \ msg0 = $0204
    FILEMGR-TID-ADDR @                      \ tid
    IPC4-CALL                               \ ( -- r0 r1 r2 r3 )
    >R DROP DROP DROP R>                    \ r0 のみ残す

    0 = IF
        $57 FILEMGR-PUTC                \ 'W' (WRITE 成功)
    ELSE
        $77 FILEMGR-PUTC                \ 'w' (失敗)
    THEN

    \ v0.10.7 (Step 5-6a): 読み返し相互検証（設計書 §8.4.6.3・任意）
    \   WRITE した "wtest.txt"(中身 "WRITE!" 6B) を OPEN→READ で読み返し、
    \   書いた内容と一致するか確認。READ は Step 5-5 実証済みのため、書いたものが
    \   読めれば DE 登録・データ書込・SB 更新の一貫した正しさの強い証拠。
    \   期待: actual=6 かつ FT-DST-BUF[0]=='W'($57) → 'V'(verify)、else 'v'。
    \   name "wtest.txt" は TEST-SRC-BUF+$C0 に既に用意済み（WRITE-TEST で設定）。

    \ wtest.txt を OPEN（最小空きindex方式。hello.txt は CLOSE 済みなので fid=0 期待）
    0 0 TEST-SRC-BUF $C0 + FILE-OPEN-OP FILEMGR-TID-ADDR @ IPC4-CALL
    >R DROP DROP DROP R>                    \ r0 = fid or error
    DUP FT-FID !                            \ fid を保存（READ・後始末用）
    0< IF                                   \ OPEN 失敗（fid<0=エラー）
        $76 FILEMGR-PUTC                    \ 'v' (OPEN 失敗で検証不可)
    ELSE
        \ READ: size=16, dst=FT-DST-BUF, fid=FT-FID
        16 FT-DST-BUF FT-FID @ FILE-READ-OP FILEMGR-TID-ADDR @ IPC4-CALL
        >R DROP DROP DROP R>                \ r0 = actual
        6 = IF                              \ actual==6 ?
            FT-DST-BUF C@ $57 = IF          \ 先頭 'W' ?
                $56 FILEMGR-PUTC            \ 'V' (読み返し一致＝WRITE 完全成功)
            ELSE
                $76 FILEMGR-PUTC            \ 'v' (actual=6 だが内容不一致)
            THEN
        ELSE
            $76 FILEMGR-PUTC                \ 'v' (actual≠6)
        THEN
    THEN

    \ ──────────────────────────────────────────────────────────
    \ v0.10.8 (Step 5-6b): FILE-WRITE-MULTI-TEST（設計書 §8.4.6.6・恒久テスト）
    \   size=1024（2セクタ・端数なし）をパターン byte[i]=(i&$FF) で WRITE→汚染→
    \   OPEN→READ→サンプル点検証。一致なら 'X'（失敗 'x'）。期待出力 …QLORCWVX。
    \   バッファ案C: FT-RW-BUF=$EC00（1024B・src/dst時系列共用）、name=FT-NAME2-BUF=$5060。
    \   ★既存テスト（hello/wtest）は完了済みのため $EC00-$EFFF を時系列再利用可。
    \ ──────────────────────────────────────────────────────────
    \ P1: FT-RW-BUF[0..1023] に byte[i]=(i AND $FF) を FILL
    0 >R                                    \ R: i=0
    BEGIN  R@ 1024 <  WHILE
        R@ $FF AND                          \ ( i&$FF )  書き込む値
        FT-RW-BUF R@ +                      \ ( val addr )
        C!                                  \ buf[i] = i&$FF
        R> 1 + >R                           \ i++
    REPEAT
    R> DROP

    \ "w1k.txt\0"(8B) を FT-NAME2-BUF ($5060) へ
    $77 FT-NAME2-BUF     C!                 \ 'w'
    $31 FT-NAME2-BUF 1 + C!                 \ '1'
    $6B FT-NAME2-BUF 2 + C!                 \ 'k'
    $2E FT-NAME2-BUF 3 + C!                 \ '.'
    $74 FT-NAME2-BUF 4 + C!                 \ 't'
    $78 FT-NAME2-BUF 5 + C!                 \ 'x'
    $74 FT-NAME2-BUF 6 + C!                 \ 't'
    $00 FT-NAME2-BUF 7 + C!                 \ NUL

    \ P2: name=w1k.txt・src=FT-RW-BUF・size=1024 で FILE_WRITE
    1024                                    \ msg3 = arg2 = size = 1024
    FT-RW-BUF                               \ msg2 = arg1 = src
    FT-NAME2-BUF                            \ msg1 = arg0 = name
    FILE-WRITE-OP                           \ msg0 = $0204
    FILEMGR-TID-ADDR @                      \ tid
    IPC4-CALL                               \ ( -- r0 r1 r2 r3 )
    >R DROP DROP DROP R>                    \ r0 のみ残す
    0<> IF                                  \ WRITE 失敗
        $78 FILEMGR-PUTC                    \ 'x'（WRITE 失敗）
    ELSE
        \ P3: FT-RW-BUF[0..1023] を $FF で上書き（読み戻し前の汚染）
        FT-RW-BUF $FF 1024 MEMSET-B

        \ P4: w1k.txt を OPEN → fid を size=1024 で FT-RW-BUF へ READ
        0 0 FT-NAME2-BUF FILE-OPEN-OP FILEMGR-TID-ADDR @ IPC4-CALL
        >R DROP DROP DROP R>                \ r0 = fid or error
        DUP FT-FID !                        \ fid を保存
        0< IF                               \ OPEN 失敗
            DROP $78 FILEMGR-PUTC           \ 'x'（OPEN 失敗）
        ELSE
            DROP
            \ READ: size=1024, dst=FT-RW-BUF, fid=FT-FID
            1024 FT-RW-BUF FT-FID @ FILE-READ-OP FILEMGR-TID-ADDR @ IPC4-CALL
            >R DROP DROP DROP R>            \ r0 = actual
            \ P5: r0==1024 かつ サンプル点 buf[0/511/512/513/1023] 一致判定
            1024 = IF
                FT-RW-BUF        C@ $00 =   \ buf[0]   == $00
                FT-RW-BUF 511 +  C@ $FF =   \ buf[511] == $FF
                AND
                FT-RW-BUF 512 +  C@ $00 =   \ buf[512] == $00（★セクタ境界・KY26本丸）
                AND
                FT-RW-BUF 513 +  C@ $01 =   \ buf[513] == $01
                AND
                FT-RW-BUF 1023 + C@ $FF =   \ buf[1023]== $FF（末尾）
                AND
                IF
                    $58 FILEMGR-PUTC        \ 'X'（5-6b 往復検証 全一致＝完全成功）
                ELSE
                    $78 FILEMGR-PUTC        \ 'x'（サンプル点不一致）
                THEN
            ELSE
                $78 FILEMGR-PUTC            \ 'x'（actual≠1024）
            THEN
            \ P6: CLOSE
            0 0 FT-FID @ FILE-CLOSE-OP FILEMGR-TID-ADDR @ IPC4-CALL
            >R DROP DROP DROP R> DROP       \ r0 は捨てる
        THEN
    THEN

    BEGIN AGAIN ;

CODE FILEMGR-TEST-TASK-ADDR  ( -- addr )
    SUBI X, #2
    LDW  A, #WORD_FILEMGR_TEST_TASK
    STW  A, [X]
END-CODE

: FILEMGR-TEST-START  ( -- )
    FILEMGR-TEST-TASK-ADDR TASK-CREATE
    DROP ;

: OS-START  ( -- )
    MEMMGR-START                    \ Ph.2 既存 (tid=1)
    UART-START                      \ Ph.3-A5 UARTドライバ起動 (tid=2)
    STOR-START                      \ v0.7: Ph.3-B ストレージドライバ起動 (tid=3)
    FILEMGR-START                   \ v0.10.0: Ph.4 FileMgr 起動 (tid=4)
    UART-TEST-START                 \ UARTテストタスク起動 (tid=5)
    STOR-TEST-START                 \ v0.7: STORテストタスク起動 (tid=6)
    FILEMGR-TEST-START              \ v0.10.2d: FileMgrテストタスク (tid=7) — 仮説ε検証
    BEGIN TASK-SLEEP AGAIN ;        \ ルートタスクは待機ループ
