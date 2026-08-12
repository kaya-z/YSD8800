日付: 2026-07-03 / 前提: HANDOVER_PEEPHOLE_P1_IMPL_v1_0.md（設計フェーズ完了）の続き。P1 実装〜確定完了。
1. 本チャットで完了したこと
scc23 peephole P1（スタックラウンドトリップ除去）を実装・全検証 PASS・v2.03 確定。

案A採用（本番 v2.02 から poc 新規生成。前チャット poc がナレッジ未登録で不在だったため）。
実装3点: ①P1判定ヘルパ（p1_is_line/p1_next_reads_ZN）②P1本体パス（既存P3の後段・w/r前詰め）③--no-peep検証フラグ。KY38厳守（本番非改変）。
P1動作: 4命令窓 SUBI SP,#2 / STW A,[SP] / LDW B,[SP] / ADDI SP,#2 → MOV B,A。-O1のみ作動。

2. 成果物（outputs出力済み・要ナレッジ登録）
ファイル内容scc23_v2_03.cP1実装・KY41 4点整合済・版数表示 v2.03 (2026-07-03)tool_version_ledger_v1_10.mdscc23 v2.03 反映scc23_v2_00_design_v2_10.docx§9.2.12.5 を検証結果（実施済）へ更新・前版保持p1_g5_test_poc.cガード単体検証ハーネス（12テスト）
3. 検証結果（全PASS・2026-07-03）

絶対ゲート -O0-strict: 826/48405/P:20/21846B 完全一致（不変維持）
V4 -O1 実機: P:20不変・cycles 47885→47795（−90）・836 DPS
V1（-O0/-O0-strict byte不変）/V2（24窓置換・差分は MOV B,A×24追加＋4命令窓×24削除のみ）/V2c/V3=CONT-1（G5がP2/P3書換え後 r+4 で正作動・T9実証）/V5=CONT-2（4回帰asm一致）/ガード単体12テスト、すべてPASS。

4. ガード要点（設計書 v2.10 §9.2.12.3）
G1隣接/G2 SUBI・ADDI同量/G3 STW A・LDW B/G4 [SP]オフセット無し/G5＝窓直後がZ/N読む条件分岐(BEQ/BNE/BLT/BGE)なら非置換（ADDI SPはZ/N更新するがMOV B,AはFLAGS不変のため。フラグ意味論保護）。
5. 次チャットでの必須事項

本チャット成果物4点をプロジェクトナレッジへ登録（未登録だと次セッションで KY34 不可・本日の「poc不在」手戻り再発）。
ナレッジ整理（削除可・確認済）: dhry_base.asm/dhry_p1.asm/p1_apply.py は中間生成物・足場のため削除可。入力ソース（scc23_v2_02.c/scc23_v2_03.c/dhry_timer.c/startup_harness23_v15.asm）は保持。

6. 未完・次工程

④日報報告 → latest チャット担当が作成（本チャット対象外）。
次工程候補（新チャットで最新ロードマップ参照のうえ確定）: scc23 Phase1〜6、または FPGA V1 CPU RTL Stage 続き。

7. 再生成手順（asm削除後に必要な場合）
scc23_v2_03 --code-org 0x0400 --data-org 0x4000 --runtime-org 0x3000 -O1 -o dhry_p1.asm dhry_timer.c
hasm23 -c dhry_p1.asm
lnk23 --machine force dhry_p1.asm.obj startup_harness23_v15.asm.obj -o dhry_p1.bin
（base側は scc23_v2_02 に置換）