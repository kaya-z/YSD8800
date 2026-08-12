// ============================================================
//  ysd8800_cpu_v0_1.sv   v0.5.8  (2026-07-14)
//  YSD8800 FPGA V1 CPUコア : トップFSM
//   ※ファイル名は部品群(regfile/decoder/alu)と揃えて _v0_1 を維持。
//     版は本ヘッダのバージョン文字列で管理(V1完成時に一括リネーム予定)。
//
//  設計根拠: fpga_v1_cpucore_design_v1_1.md §6(FSM)/§7(バスI/F)
//
//  方針(2026-06-30): 外部観測等価を守る。内部はFPGA簡素化優先。
//   多サイクル方式: 各状態1クロック、メモリはmem_ready待ちで滞留(§6.1)。
//
//  【変更履歴】
//   v0.1 (2026-06-30): スケルトン。状態enum全列挙・8bitバスI/F・部品3点
//                      インスタンス枠・リセット/IRQCHK/フェッチ/NOP/HALTのみ。
//   v0.2 (2026-07-03): 第1段実装。2バイトレジスタ命令(ALU/MOV/CMP)実行を
//                      肉付け。S_OPFETCHでrbフェッチ(need_rb判定)→S_EXEC_ALU
//                      →S_WRITEBACK(rD書込+set_zn相当のフラグ更新)→S_IRQCHK。
//                      idec→alu_op変換(alu_op_dec)追加。
//                      対応命令: MOV/ADD/SUB/CMP/AND/OR/XOR/NOT/SHL/SHR/SAR。
//                      MOV=フラグ不変, CMP=結果書かずフラグのみ(デコーダ信号準拠)。
//     【設計変更(要設計書改版)】設計書§6のS_DECODE独立状態は実装せず、
//       S_OPFETCHのrbフェッチ確定時にidecで実行状態へ直行(1サイクル節約・
//       設計書クラスA例 S_OPFETCH→S_EXEC_ALU と整合)。fpga_v1_cpucore_design
//       次版で追記のこと。
//   v0.3 (2026-07-03): 第2段(即値ALU)+第3段(分岐)実装。
//     第2段: LDWI/ADDI/SUBI/CMPI/ANDI/ORI/XORI。S_OPFETCH(rb)→S_IMML→S_IMMH
//            →S_EXEC_ALU合流(operand_b=imm_r選択)→S_WRITEBACK。LDWI=フラグ更新
//            (MOVと異なる)、CMPI=結果書かずフラグのみ。
//     第3段: JMP/BEQ/BNE/BLT/BGE(相対rel16)。3B命令(rbなし)→S_IMML→S_IMMH
//            →S_EXEC_BRANCH。emu23実照合により分岐先=(分岐命令の次命令アドレス)
//            +符号付off16。成立判定 branch_taken(JMP常時/EQ:Z1/NE:Z0/LT:N1/GE:N0)。
//            不成立時はフォールスルー(PC=次命令のまま)。
//     【設計変更(要設計書改版)】即値実行状態S_EXEC_ALUIは新設せずS_EXEC_ALUに
//       合流(operand_b選択で簡素化)。設計書§6クラスB例と差異、次版で追記。
//   未実装(次段): メモリ(LDW/STW/LDB/STB)・スタック(PUSH/POP)・
//                 制御(JSR/RET/IRET/SYSCALL)・割込受理。
//     ※JSR(絶対imm16)/RET はスタック(push16/pop16)を伴うため第5段(スタック)
//       とセットで実装予定。emu23実照合済: JSR=target絶対+戻り先push, RET=pop。
//   v0.4 (2026-07-04): 第4-A段(メモリ LDW/STW ワード)実装。
//     対応: LDW/STW [imm16](0x22/23)/[rS]/[rD](0x24/25)/[X+imm16](0x26/27)。
//     エンディアン=LE(実照合emu23 rd16/wr16: mem[a]=下位,mem[a+1]=上位)。
//     LDW=Z/N更新(set_zn), STW=フラグ不変。STW[rD]は rD=アドレス/rS=データの
//     役割逆転をFSMアドレス源選択で吸収。8bitバスで16bitを2アクセスに分解
//     (S_MEMR_LO/HI, S_MEMW_LO/HI)。
//     【案X採用(承認済)】実効アドレス確定＆アライメント判定を S_DECODE(既存
//       enum流用)の1サイクルに集約。2B命令(S_OPFETCH→S_DECODE)/4B命令(S_IMMH
//       →S_DECODE)を合流。imm_r確定後の独立サイクルでタイミング明快、状態数不増。
//     【判断①採用(承認済)】アライメント例外(奇数addr): S_DECODEで検出し
//       irq_pending←3セット→S_IRQCHK。受理シーケンス(S_IRQ_ACCEPT)は第5段。
//     【論点A採用(承認済)】ロード書戻しは S_WRITEBACK 共用(is_mem_loadで
//       データ源選択)。状態数抑制優先(可読性トレードオフ許容)。
//     検証: CPU_MEM_TB(全モード+LE+役割逆転) / CPU_MEMALIGN_TB(例外+書換抑止)
//           ともに ALL PASS。第1〜3段デグレなし。
//   未実装(次段): 第4-B段 LDB/STB(EXT 0x1F経由バイトアクセス)・
//                 スタック(PUSH/POP)・制御(JSR/RET/IRET/SYSCALL)・割込受理。
//   v0.5 (2026-07-04): 第4-B段(バイト LDB/STB, EXT 0x1F経由)実装。
//     対応: LDB/STB × A/B × [imm16]/[X] (サブop 0x10-0x17)。
//     EXTデコード経路: S_OPFETCH(need_subop)→S_SUBOP(サブopラッチ+subop_valid)
//       →S_DECODE(命令種別分岐)。is_ext_validを1'b1固定からsubop_valid駆動に
//       修正(サブop確定後のみdecoderが正規化)。
//     【案U採用(承認済)】バイトはアライメント例外なし(rd8/wr8実照合)。S_DECODEで
//       mem_w16=0判定し、[X](2B)→S_MEMR8/W8, [imm16](4B)→S_IMML経由。4Bバイトは
//       S_IMMHからS_MEMR8/W8直行(アライメント判定スキップ)。単一バイトアクセス。
//     【論点C(b)採用(承認済)】LDBロードはS_MEMR8完了で対象レジスタへ直接書戻し
//       (S_WRITEBACK共用せず)。ゼロ拡張({8'h00,mem8})、FLAGS不変(LDW/set_znと対照)。
//     【論点D採用(承認済)】対象レジスタA/B選択= subop_r[1](SUBOP_REG_BITで命名)。
//       decoder改修回避、影響をcpuに閉じる。
//     mem_misalignedを&dec_mem_w16でマスク(バイトは常に整列扱い)。
//     検証: CPU_BYTE_TB(全8命令+ゼロ拡張+フラグ不変+奇数addr+単一byte) ALL PASS。
//       第1〜4A段デグレなし(6TB全通過)。
//   未実装(次段): 第5段 スタック(PUSH/POP)・制御(JSR/RET/IRET/SYSCALL)・
//                 割込受理(S_IRQ_ACCEPT。アライメント例外の受理もここで完結)。
//   v0.5.1 (2026-07-04): 第5段の設計完了(2段階レビュー承認済)。実装は未着手で、
//     制御レジスタ(stack_ctx/push_count/pop_count/push_src)とCTX_*localparamの
//     宣言のみ追加(未使用・コンパイル健全確認済)。実装本体は次チャットで実施。
//   v0.5.2 (2026-07-04): 第5-1段(スタック基盤+制御単純系)実装。
//     対応: EI/DI(0x02/03)・SYSCALL(0x05)・PUSH/POP A/B/X(EXT 0x00-05)。
//     - EI/DI: dec_ie_set/clrでFLAGS.IE(bit7) set/clr。S_OPFETCH滞在中ワンショット。
//     - SYSCALL: S_EXEC_SYSCALLでirq_pending←4(スタック操作なし)。受理は第5-3段。
//     - PUSH: pre-dec(mem[SP-2]=下位,mem[SP-1]=上位, SP←SP-2)。S_PUSH_LO/HI。
//     - POP : post-inc(下位=mem[SP],上位=mem[SP+1], 対象reg←{hi,lo}, SP←SP+2)。
//       S_POP_LO/HI。mem_lo流用でLE合成。
//     【バグ修正(実照合)】POP対象reg判定: HANDOVER§2.2「下位2bit」はPUSH専用で、
//       POP(0x03起点)には不成立(0x04→下位2bit=00=A誤り)。emu23 L1253-1255照合で
//       POP=subop-3方式に修正(stk_pop_sel=subop_r[2:0]-3)。TBで捕捉・解消。
//     【Icarus対応】always_comb内の定数ビット選択(rf_flags[14:0]/subop_r[2:0])を
//       assign外出し(flags_lo15/subop_lo3)。sorry警告解消。
//     【観測ポート追加】dbg_irq_pending(SYSCALL/割込のirq_pending観測用)。
//       既存TBは未接続output許容でデグレなし。
//     検証: 新規CPU_STACK_TB(値移動/SP往復/LE格納順/IE操作/SYSCALL) ALL PASS。
//       既存3TB(byte/mem/memalign)デグレなし。
//   未実装(次段): 第5-2段 JSR/RET(push/pop各1回)・第5-3段 IRET(pop2)+
//                 割込受理S_IRQ_ACCEPT(push2+ベクタ読み)。
//   v0.5.3 (2026-07-04): 第5-2段(JSR/RET)実装。共通スタック機構をstack_ctxで
//     戻り先分岐する方式(論点G-a承認)に統合。第5-1段のPUSH/POPもctx方式へ移行。
//     - JSR(0x68,3B): S_OPFETCH→S_IMML/H(target=imm_r確定)→S_EXEC_JSR
//       (push_src←rf_pc=戻り先, ctx←CTX_JSR)→S_PUSH_LO/HI→完了時PC←imm_r。
//       emu23実照合(L1529-1533): fetch16でtarget取得pc+=2、push16(pc)、pc=target。
//       戻り先=imm16フェッチ後のrf_pc(=JSR命令の次命令)。LE格納。
//     - RET(0x69,1B): S_OPFETCH→S_EXEC_RET(ctx←CTX_RET)→S_POP_LO/HI→完了時
//       PC←{hi,lo}(pop値)。emu23実照合(L1535): pc=pop16()。
//     - stack_ctx: S_DECODE(PUSH/POP)・S_EXEC_JSR/RETで設定、S_IRQCHKでクリア。
//       push_data=ctx選択(CTX_PUSH:A/B/X, CTX_JSR:push_src)。S_PUSH_HI/S_POP_HI
//       完了時にctxで書戻し先分岐(JSR:PC←target, RET:PC←pop, POP:reg←pop)。
//     検証: 新規CPU_JSR_TB(呼出/復帰往復/戻り先LE格納/SP往復/最終PC) ALL PASS。
//       既存4TB(byte/mem/memalign/stack)デグレなし=PUSH/POPのctx化も健全。
//   v0.5.4 (2026-07-04): 第5-3段ステップ(a) IRET実装。設計レビュー(stage5_3_
//     design_review_reply v1.0)で条件付き承認(D-1/D-2確定承認)を受け着手。
//     - IRET(0x04,1B): pop2回(FLAGS先→PC後)。pop_count(2→1→0)で多重pop制御。
//       emu23_v109実照合(L1215-1216): flags=(uint8_t)pop16(); pc=pop16()。
//     - 【D-2承認反映】FLAGS復元は下位8bitのみ: rf_flags←{8'h00, mem_lo}。
//       pop値上位8bitは捨てる((uint8_t)キャスト等価)。ISA2.3で有効bit(Z/N/IE)は
//       全て下位8bit内をレビュー確定。TBで実証(pop値0xABCD→FLAGS=0x00CD)。
//     - 【C-2反映】pop_count減算はS_POP_HI完了ワンショット(SP更新と同期・滞留中
//       不変,7/01 KY)。遷移分岐条件はff出力のpop_count現在値のみ使用。
//     - 単発pop(POP/RET)もpop_count=1設定に統一。S_POP_HIの遷移分岐(pop_count>1)
//       で単発は最後扱い→S_IRQCHK、IRETは1回目継続→S_POP_LO。
//     検証: 新規CPU_IRET_TB(復帰PC/SP+4/FLAGS下位8bit=D-2実証) ALL PASS。
//       既存5TB(byte/mem/memalign/stack/jsr)デグレなし(pop_count導入も健全)。
//     TB知見: IRET/割込のFLAGS検証は復帰先にフラグ不変命令(MOV)を置く。フラグ
//       更新命令(LDWI等)を置くと復元FLAGSが上書きされ検証不能(初回FAILの原因)。
//   v0.5.6 (2026-07-06): 第5-3段ステップ(b) 割込受理の【TB受理実証 完了】。
//     v0.5.5で持越したCPU_IRQ_TB 7FAILの真因を特定・修正。
//     [真因] EI/DIのFLAGS.IE書込が IE=bit7 ではなく bit15 を操作していた。
//       旧コード rf_wdata_flags={1'b1, flags_lo15} (flags_lo15=rf_flags[14:0]) は
//       1'b1 が MSB(bit15)に載り、受理判定 flags_ie=rf_flags[7] は 0 のまま。
//       →EI後もIE=0で割込が永久に受理されない(irq_pendingは正しくラッチされるが
//         flags_ie=0で弾かれ続ける)。DIも bit15=0 操作で「たまたまIE=0維持」に見え、
//         誤って PASS:IE=0 が出ていた。既存6TBはEI/DIのIE反映を検証せず露見せず。
//     [修正] IE(bit7)のみ差替え・他15bit保持の正しい合成へ訂正。
//       always_comb内の定数ビット選択(Icarus sorry)を避けるため、保持対象ビット
//       フィールドを assign で外出し(flags_ie_hi=rf_flags[15:8], flags_ie_lo=
//       rf_flags[6:0])し、rf_wdata_flags={flags_ie_hi, IE, flags_ie_lo} で合成。
//       旧 flags_lo15 宣言/assign は削除(KY41整合)。
//     [検証] 診断(EI後IE=1→S_IRQ_ACCEPT到達→PC=0305/A=0011/SP=3FFC/IE=0/
//       irq_pending=0/stack PC=0109 LE)確認後、CPU_IRQ_TB【ALL PASS】(7FAIL→0)。
//       既存6TB(fetch/mem/memalign/byte/iret+構文)回帰【ALL PASS】(C-3, デグレ無)。
//     [残] 第5-3段(c) 受理→IRET往復統合 + align例外受理 が次段。
//   v0.5.6 追記 (2026-07-06): 第5-3段ステップ(c)【完了】。RTLロジック無変更(レビュー
//     stage5_3c_design_review_reply_v1_0 Q1承認: 必要パーツ(受理(b)/IRET(a)/align検出)
//     は既存実装済)。統合TB2本を新規追加し実証:
//     - tb_cpu_irq_iret_v0_1: 受理→IRET往復統合。SP往復ゼロ復帰(4000)・FLAGS往復IE=1
//       復帰・PC復帰(0109)・stack PC(LE)を検証【ALL PASS】。
//     - tb_cpu_align_irq_v0_1: align例外受理(E-1, LDW/STW両経路)。irq_pending=3→
//       vec=mem[6:7]受理→往復。Q3(align push PC=次命令PC=010F)確定通り、C-1(例外命令
//       副作用なし: LDW A不変/STW 書込なし=fault-then-continue)を実証【ALL PASS】。
//     [検証] 全8TB(fetch/mem/memalign/byte/iret/irq/irq_iret/align)回帰【ALL PASS】
//       (C-2, デグレ無)。
//     [申送] N-2: 黄金emu23_v109のナレッジ登録・版数台帳更新(継続課題)。
//     [残] 第5-3段(c)完了により第5段完了。次は V2 CPUコア単体検証(全命令 emu23外部
//       観測等価)。
//   v0.5.8 (2026-07-14): 【V5/S5】割込 pending 第1段保護。
//     S_IRQCHK での irq_in ラッチ条件に irq_pending==0(空)を追加。
//     従来: if (state==S_IRQCHK && irq_in != 3'd0) irq_pending <= irq_in;
//       → 受理待ちの pending が在っても新規 irq_in で【上書き】されるため、
//         先行割込の取りこぼし/横取りが起きうる。emu23 と非等価。
//     修正: if (state==S_IRQCHK && irq_in != 3'd0 && irq_pending == 3'd0)
//       → 【空の時だけ受け付ける】。emu23_v110.c L1591 と同形:
//         `if (cpu.irq_pending < 0 && YSD8002_tick(cpu.cycle))`
//     ★flags_ie を条件に含めない★ emu23 のラッチ段(L1591)は IE を見ない。
//       IE を見るのは【受理】段(emu23 L1214 / 本RTL L590)のみ。この二段構造を
//       崩すと DI 区間の要求が消滅し、emu23 と非等価になる(V5 タイマーで顕在化)。
//     [背景] V5(YSD8002 タイマー)は TCR-ACK 方式(bit5 IRQ_ACK)で再武装する。
//       ハンドラが ACK を書くまで次の pending を受けない構造が前提となるため、
//       ラッチ段の上書き保護が必須。
//     [検証] 改修前ベースライン取得後に同一TBで再走し等価を確認:
//       V1系8TB(25 PASS/0 FAIL)・V2e(82ベクタ ALL PASS)。
//     [参照] v5_design_memo_v0_2.md / HANDOVER_CHAT88.md §6 / emu23_v110.c L1591,L1214。
//   v0.5.7 (2026-07-11): 【重大バグ修正・V3統合検証で発覚】バス出力always_comb
//     (状態別mem_addr/mem_rd/mem_wr振り分け)にS_SUBOP(EXTプリフィックス0x1F
//     サブopcodeフェッチ)のcaseが欠落しており、mem_rdが常に0のまま出力される
//     潜在バグを検出・修正。regfile制御側(rf_we_pc)・subop_rラッチ側は共に
//     if(state==S_SUBOP && mem_ready)という正しいガードを持っていたが、
//     そもそもmem_rdを立てていなかった。V1/V2の理想メモリTB(mem_ready固定1・
//     要求信号非依存)ではこの欠落が最終レジスタ値に一切影響せず、V2「82ベクタ
//     ALL PASS」の裏で完全に見過ごされていた。V3(CDCブリッジ+PSRAMコントローラ、
//     実req/ack型メモリ)へ接続して初めて「mem_rd=0→要求未発行→ack永久に来ず
//     ハング」という形で顕在化(PUSH/POP/LDB/STB等0x1F経由の全命令が対象)。
//     修正: S_SUBOP: begin mem_addr = rf_pc; mem_rd = 1'b1; end を追記
//     (S_FETCH等と同型)。
//     [検証] V3統合TB3本(ALU系20/20・メモリ系5/5・境界+JSR/RET/BEQ複合1/1、
//       実CPUコア+V3メモリサブシステムでemu23協調等価)全PASS。既存V1/V2由来の
//       理想メモリTB(tb_cpu_v2a_v0_1、20ベクタ)も回帰ALL PASSでデグレ無を確認。
//     [参照] v3_design_memo_v0_3.md §9 / fpga_v1_cpucore_design_v1_2.md §7.1 /
//       kaizen.txt 原則63(理想メモリTBのALL PASSは必要条件であって十分条件でない)。
//   v0.5.5 (2026-07-05): 第5-3段ステップ(b) 割込受理S_IRQ_ACCEPT 実装。
//     emu23_v109実照合(L1174-1188): push16(pc)先→push16(flags)後→flags&=~FL_IE
//     →vec=rd16(irq*2)→pc=vec。RTL実装も同順で構成:
//     - 受理判定は既存S_IRQCHK(irq_pending!=0 && flags_ie)を流用。→S_IRQ_ACCEPT。
//     - S_IRQ_ACCEPT入口ff: 【C-1】irq_latch←irq_pending退避(受理中の新irq_in競合
//       遮断), stack_ctx←CTX_IRQ, push_count←2, push_src←rf_pc(1回目push=PC)。
//     - push機構(S_PUSH_LO/HI)をstack_ctxで共有。1回目完了でpush_src←rf_flags,
//       2回目(push_count==1)完了で【D-1】IE=0(rf_flags&16'hFF7F, push後), 
//       stack_ctx←CTX_IRQVEC。push_count減算はS_PUSH_HI完了ワンショット(C-2同思想)。
//     - ベクタ読み: S_MEMR_LO/HIを流用しPC←mem[irq*2] 16bit LE。CTX_IRQVEC完了で
//       PC←{mem_rdata,mem_lo}(regfile側), irq_pending←0, stack_ctx←CTX_NONE→S_FETCH。
//     - 【組合せループ回避(案1)】当初mem_addrをstack_ctx依存の三項で選択したが、
//       mem_addr→mem_ready→state→stack_ctxの閉路でIcarusがbyte TBでハング(時刻
//       停止)。対処: ベクタアドレスをS_IRQ_ACCEPT入口でaddr_r<={irq_pending,1'b0}
//       にff退避し、S_MEMR_LO/HIは既存addr_r参照に統一。組合せ選択を撤廃しループ解消。
//       (KY: Icarus always_combで状態依存のバス生成は組合せループを招く→アドレスは
//        ffラッチした専用レジスタに寄せる。MC6809実機のアドレスバスラッチと同思想)。
//     - 未使用化したirq_vec_addr宣言/assignは削除(KY41整合)。
//     検証: 【C-3】既存6経路(fetch/mem/memalign/byte/iret+構文) ALL PASS(デグレ無)。
//       ただし新規CPU_IRQ_TB(受理そのもの検証)は【未完】。TBで割込が受理されず7FAIL。
//       原因調査中(有力仮説: irq_in投入タイミング vs irq_pendingラッチ位相、または
//       EI反映位相)。実装本体は黄金照合済だが、TB側含めた受理成立の実証は次回持越し。
//   未実装(次段): 第5-3段ステップ(b)割込受理の【TB受理実証(継続)】、
//     (c)受理→IRET往復統合+align例外受理。レビュー条件C-1(irq入口ラッチ)/C-3
//     (既存TB回帰)/E-1(LDW/STW両経路align受理TB)を(b)(c)で反映予定。
//     【第5段 設計確定事項(実照合+レビュー承認済・次チャットで実装)】
//      ・スタック: SP pre-decrement push / post-increment pop (MC6809方式,
//        emu23 L832-840実照合)。push16:SP-=2→wr16(LE)。pop16:rd16→SP+=2。
//      ・PUSH/POP A/B/X: EXT0x1F サブop0x00-05 (2B)。専用状態S_PUSH_LO/HI,
//        S_POP_LO/HI (論点F承認)。対象reg=subop下位2bit。
//      ・EI/DI/IRET/SYSCALL: 1バイト通常命令opcode 0x02/03/04/05 (EXT非経由,
//        emu23 L1195-1233実照合)。IRET: FLAGS←pop(下位8bit)→PC←pop (L1213-1216)。
//        SYSCALL: irq_pending←4 (L1225-1231)。EI:IE=1 / DI:IE=0。
//      ・JSR(0x68,3B): push16(nextPC)→PC←imm16(絶対)。RET(0x69,1B): PC←pop16。
//      ・割込受理(S_IRQCHK→S_IRQ_ACCEPT, emu23 L1174-1189実照合): 条件
//        irq_pending≠0 && IE=1。push(PC)→push(FLAGS)→IE=0→PC←rd16(pending*2)。
//        push2回/vec読みはstack_ctx+push_countで制御(論点G-a/I/J/K承認)。
//      ・複合命令制御(論点G-a): 共通S_PUSH/POP機構をstack_ctx(CTX_*)で戻り先
//        分岐。多重push/popはpush_count/pop_countカウンタ。
//      ・実装順(次チャット): 第5-1(EI/DI/SYSCALL+PUSH/POP)→第5-2(JSR/RET)
//        →第5-3(IRET+割込受理)。各段でTB検証。
//      ・7/01 KY継続: PC/SP更新は遷移確定サイクルのワンショット・滞留中加算禁止。
//      ・注: timer_in_service再アーム(emu23 L1217-1220)はソフト固有。FPGAは
//        ハードタイマー自律のため模倣不要(外部観測等価の範囲外)。
// ============================================================
`timescale 1ns/1ps

import ysd8800_idec_pkg::*;

module ysd8800_cpu_v0_1 (
    input  logic        clk,
    input  logic        rst_n,

    // --- 抽象バスI/F (§7.1 8bit粒度) ---
    output logic [15:0] mem_addr,
    output logic [7:0]  mem_wdata,
    input  logic [7:0]  mem_rdata,
    output logic        mem_rd,
    output logic        mem_wr,
    input  logic        mem_ready,

    // --- 割込入力 (irq_pending ∈ {1,2,3,4}, 0=なし) ---
    input  logic [2:0]  irq_in,       // 外部割込要求番号(0=なし)

    // --- 観測出力 (突合トレース用) ---
    output logic [15:0] dbg_pc,
    output logic [15:0] dbg_a,
    output logic [15:0] dbg_b,
    output logic [15:0] dbg_x,
    output logic [15:0] dbg_sp,
    output logic [15:0] dbg_flags,
    output logic        dbg_halt,
    // 【第5段】割込受理待ち番号(SYSCALL/割込のirq_pending観測用)。
    output logic [2:0]  dbg_irq_pending,
    // ★案0-a' (v5_irq0_ack_design_v0_1): IRQ0(timer)受理確定パルス★
    //   β点=S_MEMR_HI でベクタ読み完了(CTX_IRQVEC)かつ irq_latch==1 の1クロック。
    //   YSD8002 へ直結し irq_req_r を下ろす(受理=割込線クリア)。YSD8004非経由。
    output logic        irq0_ack
);

    // ============================================================
    //  状態 enum (§6.1〜6.5)
    // ============================================================
    typedef enum logic [5:0] {
        S_RESET_LO,     // リセットベクタ下位byte読み (mem[0x0000])
        S_RESET_HI,     // リセットベクタ上位byte読み (mem[0x0001])→PC←{hi,lo}
        S_IRQCHK,       // 割込チェック
        S_IRQ_ACCEPT,   // 割込受理(PC push/FLAGS push/IE=0/PC←vec)
        S_FETCH,        // opcode フェッチ
        S_OPFETCH,      // rb(rD/rS)フェッチ or サブopフェッチ
        S_SUBOP,        // 0x1F サブopcode フェッチ
        S_DECODE,       // デコード分岐
        S_IMML,         // imm16 下位byte
        S_IMMH,         // imm16 上位byte
        S_EXEC_ALU,     // レジスタALU実行
        S_EXEC_ALUI,    // 即値ALU実行
        S_EXEC_MOV,     // MOV
        S_EXEC_BRANCH,  // 分岐判定
        S_MEMR_LO,      // 16bitリード下位
        S_MEMR_HI,      // 16bitリード上位
        S_MEMW_LO,      // 16bitライト下位
        S_MEMW_HI,      // 16bitライト上位
        S_MEMR8,        // 8bitリード(LDB)
        S_MEMW8,        // 8bitライト(STB)
        S_PUSH_LO,      // スタックpush下位
        S_PUSH_HI,      // スタックpush上位
        S_POP_LO,       // スタックpop下位
        S_POP_HI,       // スタックpop上位
        S_EXEC_IRET,    // IRET
        S_EXEC_SYSCALL, // SYSCALL (irq_pending←4)
        S_EXEC_JSR,     // JSR
        S_EXEC_RET,     // RET
        S_WRITEBACK,    // rD/FLAGS更新→次命令
        S_HALT          // 停止
    } state_t;

    state_t state, next_state;

    // ============================================================
    //  内部レジスタ・ラッチ
    // ============================================================
    logic [7:0]  ir;         // opcode ラッチ
    logic [7:0]  subop_r;    // サブopcode ラッチ
    logic        subop_valid;// サブop確定フラグ(S_SUBOP完了で1、命令完了でクリア)
    logic [7:0]  rb_r;       // rb(rD/rS)ラッチ
    logic [15:0] imm_r;      // imm16 ラッチ
    logic [15:0] addr_r;     // メモリアドレスラッチ
    logic [7:0]  byte_lo;    // 16bit合成用 下位byteラッチ(imm用)
    logic [7:0]  mem_lo;     // メモリロード16bit合成用 下位byteラッチ
    logic [15:0] load_data;  // メモリロード16bit確定値(S_WRITEBACKで rD へ)
    logic [2:0]  irq_pending;// 受理待ち割込番号(0=なし)

    // --- 第5段: スタック複合命令の制御(論点G-a/I/J) ---
    //  stack_ctx: 現在スタック機構を使っている命令種別。S_PUSH_HI/S_POP_HI
    //   完了時にこれで戻り先を決める。push_count/pop_countで多重push/popを制御。
    logic [2:0]  stack_ctx;  // 処理中命令種別(下記CTX_*)
    logic [1:0]  push_count; // 残push回数(割込受理=2, PUSH/JSR=1)
    logic [1:0]  pop_count;  // 残pop回数(IRET=2, POP/RET=1)
    logic [15:0] push_src;   // pushするデータ一時保持(PC/FLAGS/A/B/X)
    // --- 第5-3段(b): 割込受理 ---
    //  irq_latch: 受理開始時にirq_pendingを退避(C-1)。受理中の新irq_inによる
    //   ベクタ番号書換を遮断。以降ベクタ計算はirq_latchのみ参照。
    logic [2:0]  irq_latch;  // 受理中IRQ番号(1=timer/2=device/3=align/4=syscall)
    // stack_ctx エンコード(可読性のためlocalparam命名)
    localparam logic [2:0] CTX_NONE = 3'd0;
    localparam logic [2:0] CTX_PUSH = 3'd1;  // PUSH A/B/X
    localparam logic [2:0] CTX_POP  = 3'd2;  // POP  A/B/X
    localparam logic [2:0] CTX_JSR  = 3'd3;  // JSR (push PC後 PC←target)
    localparam logic [2:0] CTX_RET  = 3'd4;  // RET (pop→PC)
    localparam logic [2:0] CTX_IRET = 3'd5;  // IRET(pop FLAGS→pop PC)
    localparam logic [2:0] CTX_IRQ  = 3'd6;  // 割込受理(push PC→push FLAGS→vec)
    localparam logic [2:0] CTX_IRQVEC = 3'd7;// 割込受理のベクタ読み(mem[pending*2])

    // --- ビット選択の中間信号 (assign文で抽出: Icarus always_comb制約回避) ---
    logic        flags_ie;   // FLAGS bit7 = IE(割込許可)
    logic [3:0]  rb_rd;      // rb[7:4] = rD フィールド
    logic [3:0]  rb_rs;      // rb[3:0] = rS フィールド
    assign flags_ie = rf_flags[7];
    assign rb_rd    = rb_r[7:4];
    assign rb_rs    = rb_r[3:0];

    // --- idec → alu_op 変換 (ALUの localparam エンコードに一致) ---
    //  ADD0/SUB1/AND2/OR3/XOR4/NOT5/SHL6/SHR7/SAR8/PASSB9
    //  MOV/LDWI=PASSB(operand_b通過), CMP/CMPI=SUB(結果は書かずZ/Nのみ)
    //  即値版(ADDI/SUBI/ANDI/ORI/XORI)も演算は同一(operand_bにimm)。
    logic [3:0] alu_op_dec;
    always_comb begin
        case (dec_idec)
            ID_ADD,  ID_ADDI:  alu_op_dec = 4'd0;  // ALU_ADD
            ID_SUB,  ID_SUBI,
            ID_CMP,  ID_CMPI:  alu_op_dec = 4'd1;  // ALU_SUB
            ID_AND,  ID_ANDI:  alu_op_dec = 4'd2;  // ALU_AND
            ID_OR,   ID_ORI:   alu_op_dec = 4'd3;  // ALU_OR
            ID_XOR,  ID_XORI:  alu_op_dec = 4'd4;  // ALU_XOR
            ID_NOT:            alu_op_dec = 4'd5;  // ALU_NOT
            ID_SHL:            alu_op_dec = 4'd6;  // ALU_SHL
            ID_SHR:            alu_op_dec = 4'd7;  // ALU_SHR
            ID_SAR:            alu_op_dec = 4'd8;  // ALU_SAR
            ID_MOV,  ID_LDWI:  alu_op_dec = 4'd9;  // ALU_PASSB
            default:           alu_op_dec = 4'd0;
        endcase
    end

    // --- rbフェッチ要否 (S_OPFETCH で mem[PC] を rb として読むか) ---
    //  設計書§5命令長分類: rb を持つのは 2B(op+rb) と 4B(op+rb+imm16)。
    //  3B(op+imm16: 分岐/JSR)は rb を持たない。EXT(0x1F)は need_subop で別処理。
    //  → rb要 = 非EXT かつ instr_len∈{2,4}。
    logic need_rb;
    assign need_rb = (~dec_need_subop) &
                     ((dec_instr_len == 3'd2) | (dec_instr_len == 3'd4));

    // --- メモリ命令(LDW/STW ワード)判定と実効アドレス算出 (第4-A段) ---
    //  実照合(emu23_v109.c L1312-1372):
    //   ID_LDW_ABS/STW_ABS(0x22/23): addr=imm_r
    //   ID_LDW_RS(0x24)            : addr=rS値(rf_rdata_s)
    //   ID_STW_RD(0x25)            : addr=rD値(rf_rdata_d) ★役割逆転
    //   ID_LDW_XI/STW_XI(0x26/27)  : addr=X+imm_r
    //  ロード=Z/N更新, ストア=フラグ不変。エンディアン=LE(mem[a]=下位)。
    logic is_mem_load, is_mem_store, is_mem_word;
    always_comb begin
        case (dec_idec)
            ID_LDW_ABS, ID_LDW_RS, ID_LDW_XI: is_mem_load = 1'b1;
            default:                          is_mem_load = 1'b0;
        endcase
        case (dec_idec)
            ID_STW_ABS, ID_STW_RD, ID_STW_XI: is_mem_store = 1'b1;
            default:                          is_mem_store = 1'b0;
        endcase
    end
    assign is_mem_word = is_mem_load | is_mem_store;

    // 実効アドレス(組合せ)。addr源を命令別に選択。
    logic [15:0] eff_addr;
    always_comb begin
        case (dec_idec)
            ID_LDW_ABS, ID_STW_ABS: eff_addr = imm_r;
            ID_LDW_RS:              eff_addr = rf_rdata_s;
            ID_STW_RD:              eff_addr = rf_rdata_d; // rD=アドレス
            ID_LDW_XI,  ID_STW_XI:  eff_addr = rf_x + imm_r;
            // バイト(第4-B段): [imm16]=imm_r, [X]=rf_x
            ID_LDB_ABS, ID_STB_ABS: eff_addr = imm_r;
            ID_LDB_X,   ID_STB_X:   eff_addr = rf_x;
            default:                eff_addr = 16'h0000;
        endcase
    end
    // アライメント例外: ワードのみ(bit0=1)。バイトは常に整列扱い(rd8/wr8実照合)。
    logic mem_misaligned;
    assign mem_misaligned = eff_addr[0] & dec_mem_w16;

    // ストアデータ源: 全STWで rS=rb[3:0]=rf_rdata_s がデータ(実照合L1326/43/61)。
    logic [15:0] store_data;
    assign store_data = rf_rdata_s;
    // バイト分解(always_comb内ビット選択のIcarus制約回避のためassign抽出)
    logic [7:0] store_lo, store_hi;
    assign store_lo = store_data[7:0];
    assign store_hi = store_data[15:8];

    // ロード値のZ/N(set_zn相当: LDWはZ/N更新)。ビット選択はassign抽出。
    logic load_z, load_n;
    assign load_z = (load_data == 16'h0000);
    assign load_n = load_data[15];

    // --- バイト命令(LDB/STB)の対象レジスタ選択 (論点D: subop_rビット参照) ---
    //  実照合(サブop 0x10-0x17): bit1=0→A宛, bit1=1→B宛。
    //  ビット位置をlocalparamで命名し可読性担保(マジックナンバー回避)。
    localparam int SUBOP_REG_BIT = 1;  // サブopのA/B選択ビット
    logic byte_reg_is_b;               // 0=A宛, 1=B宛
    assign byte_reg_is_b = subop_r[SUBOP_REG_BIT];
    // バイトストアデータ源: 対象レジスタ(A/B)の下位8bit。ビット選択はassign抽出。
    logic [7:0] byte_store_data;
    assign byte_store_data = byte_reg_is_b ? rf_b[7:0] : rf_a[7:0];

    // --- 【第5段】PUSH/POP対象レジスタ選択 ---
    //  emu23実照合(L1247-1255): PUSH=0x00/01/02→A/B/X, POP=0x03/04/05→A/B/X。
    //   PUSHは subop-0x00、POPは subop-0x03 で 0/1/2(=A/B/X)。ベースが異なる点に注意
    //   (HANDOVER §2.2「下位2bit」記述はPUSHのみ有効。POPは 0x03起点のため不成立)。
    //   → PUSH: stk_push_sel = subop_r[1:0]  (0x00-02の下位2bit)
    //     POP : stk_pop_sel  = subop_r[2:0]-3 (0x03-05を0/1/2へ)
    logic [2:0]  subop_lo3;         // subopの下位3bit(assign抽出)
    assign subop_lo3 = subop_r[2:0];
    logic [1:0]  stk_push_sel;      // PUSH対象 0=A/1=B/2=X
    assign stk_push_sel = subop_r[1:0];
    logic [1:0]  stk_pop_sel;       // POP対象  0=A/1=B/2=X
    assign stk_pop_sel = subop_lo3 - 3'd3; // 0x03→0, 0x04→1, 0x05→2
    // PUSHデータ源: 対象レジスタの現在値(A/B/X)。ビット選択はassign外出し済のため
    //  ここはcaseで3択(Icarus: always_comb内caseは可、ビット選択のみ不可)。
    logic [15:0] stk_push_val;
    always_comb begin
        case (stk_push_sel)
            2'd0:    stk_push_val = rf_a;
            2'd1:    stk_push_val = rf_b;
            2'd2:    stk_push_val = rf_x;
            default: stk_push_val = 16'h0000; // 3=未定義(NOP相当)
        endcase
    end
    // 【第5-2段】pushデータ源: stack_ctxで選択。
    //  CTX_PUSH(PUSH A/B/X)=stk_push_val(A/B/X), CTX_JSR=push_src(戻り先PC)。
    //  第5-3段でCTX_IRQ(PC/FLAGS)も push_src 経由でここに合流予定。
    logic [15:0] push_data;
    always_comb begin
        case (stack_ctx)
            CTX_PUSH: push_data = stk_push_val; // PUSH A/B/X
            CTX_JSR:  push_data = push_src;     // JSR: 戻り先PC(S_EXEC_JSRでラッチ)
            CTX_IRQ:  push_data = push_src;     // 割込受理(第5-3段): PC/FLAGS
            default:  push_data = stk_push_val;
        endcase
    end
    // PUSHデータのLE下位/上位byte(ビット選択はassign抽出でIcarus制約回避)。
    logic [7:0] stk_push_lo, stk_push_hi;
    assign stk_push_lo = push_data[7:0];
    assign stk_push_hi = push_data[15:8];
    // スタックアクセスアドレス(pre-dec push: SP-2/SP-1, post-inc pop: SP/SP+1)。
    logic [15:0] sp_m2, sp_m1, sp_p1;
    assign sp_m2 = rf_sp - 16'd2;  // push新SP(=書込先LO)
    assign sp_m1 = rf_sp - 16'd1;  // push HI(=SP-1)
    assign sp_p1 = rf_sp + 16'd1;  // pop  HI(=SP+1)
    // POP宛先レジスタアドレス(regfile gp書込アドレス: A=0/B=1/X=2)。
    logic [3:0]  stk_pop_waddr;
    always_comb begin
        case (stk_pop_sel)
            2'd0:    stk_pop_waddr = 4'd0; // A
            2'd1:    stk_pop_waddr = 4'd1; // B
            2'd2:    stk_pop_waddr = 4'd2; // X
            default: stk_pop_waddr = 4'd0;
        endcase
    end
    // POP合成値の下位/上位byte(メモリLE合成用)。mem_lo流用+今回上位。
    //  合成は S_POP_HI の書戻しで {mem_rdata, mem_lo} を直接使う(専用ラッチ不要)。

    // --- FLAGS上位ビット保持用(set_zn: Z/N以外は保持)。assign抽出でIcarus制約回避 ---
    logic [13:0] flags_hi;   // FLAGS[15:2]
    assign flags_hi = rf_flags[15:2];
    // 【v0.5.6】EI/DI用 IE(bit7)差替え合成のビットフィールドをassignで外出し。
    //  旧 flags_lo15(rf_flags[14:0]) は {1'b1,flags_lo15} で 1'b1 が bit15 に載り
    //  IE(bit7)を操作しない誤りだった(EIが効かない真因)。IEを除く上位8bit/下位7bitを
    //  分離抽出し、always_comb内では定数ビット選択を書かない(Icarus sorry回避=既知知見)。
    logic [7:0] flags_ie_hi;  // FLAGS[15:8] (IEより上位、保持対象)
    logic [6:0] flags_ie_lo;  // FLAGS[6:0]  (IEより下位、保持対象)
    assign flags_ie_hi = rf_flags[15:8];
    assign flags_ie_lo = rf_flags[6:0];

    // --- 分岐成立判定 (emu23実照合: EQ=Z1/NE=Z0/LT=N1/GE=N0、JMP=常時) ---
    //  現FLAGSのZ/Nで判定。BR_ALWAYS/EQ/NE/LT/GE = 0/1/2/3/4。
    logic flags_z, flags_n;
    assign flags_z = rf_flags[0];
    assign flags_n = rf_flags[1];
    logic branch_taken;
    always_comb begin
        case (dec_branch_cond)
            3'd0:    branch_taken = 1'b1;        // BR_ALWAYS (JMP)
            3'd1:    branch_taken = flags_z;     // BR_EQ  Z=1
            3'd2:    branch_taken = ~flags_z;    // BR_NE  Z=0
            3'd3:    branch_taken = flags_n;     // BR_LT  N=1
            3'd4:    branch_taken = ~flags_n;    // BR_GE  N=0
            default: branch_taken = 1'b0;
        endcase
    end

    // ============================================================
    //  部品インスタンス枠 (配線は次版で肉付け)
    // ============================================================
    // --- レジスタファイル ---
    logic [3:0]  rf_raddr_d, rf_raddr_s;
    logic [15:0] rf_rdata_d, rf_rdata_s;
    logic        rf_we_gp;
    logic [3:0]  rf_waddr_gp;
    logic [15:0] rf_wdata_gp;
    logic        rf_we_pc;
    logic [15:0] rf_wdata_pc, rf_pc;
    logic        rf_we_sp;
    logic [15:0] rf_wdata_sp, rf_sp;
    logic        rf_we_flags;
    logic [15:0] rf_wdata_flags, rf_flags;
    logic [15:0] rf_a, rf_b, rf_x;

    ysd8800_regfile_v0_1 u_rf (
        .clk(clk), .rst_n(rst_n),
        .raddr_d(rf_raddr_d), .raddr_s(rf_raddr_s),
        .rdata_d(rf_rdata_d), .rdata_s(rf_rdata_s),
        .we_gp(rf_we_gp), .waddr_gp(rf_waddr_gp), .wdata_gp(rf_wdata_gp),
        .we_pc(rf_we_pc), .wdata_pc(rf_wdata_pc), .pc_out(rf_pc),
        .we_sp(rf_we_sp), .wdata_sp(rf_wdata_sp), .sp_out(rf_sp),
        .we_flags(rf_we_flags), .wdata_flags(rf_wdata_flags), .flags_out(rf_flags),
        .a_out(rf_a), .b_out(rf_b), .x_out(rf_x)
    );

    // --- デコーダ ---
    idec_t       dec_idec;
    logic [2:0]  dec_instr_len;
    logic        dec_is_ext, dec_need_subop, dec_is_imm16;
    logic        dec_flag_we, dec_reg_we, dec_ie_set, dec_ie_clr;
    logic [1:0]  dec_mem_op;
    logic        dec_mem_w16, dec_is_branch;
    logic [2:0]  dec_branch_cond;
    logic        dec_is_ctrl;

    ysd8800_decoder_v0_1 u_dec (
        .op(ir), .subop(subop_r), .is_ext_valid(subop_valid),
        .idec(dec_idec), .instr_len(dec_instr_len),
        .is_ext(dec_is_ext), .need_subop(dec_need_subop), .is_imm16(dec_is_imm16),
        .flag_we(dec_flag_we), .reg_we(dec_reg_we),
        .ie_set(dec_ie_set), .ie_clr(dec_ie_clr),
        .mem_op(dec_mem_op), .mem_w16(dec_mem_w16),
        .is_branch(dec_is_branch), .branch_cond(dec_branch_cond),
        .is_ctrl(dec_is_ctrl)
    );

    // --- ALU ---
    logic [3:0]  alu_op;
    logic [15:0] alu_a, alu_b, alu_result;
    logic        alu_z, alu_n;

    ysd8800_alu_v0_1 u_alu (
        .alu_op(alu_op), .operand_a(alu_a), .operand_b(alu_b),
        .result(alu_result), .flag_z(alu_z), .flag_n(alu_n)
    );

    // ============================================================
    //  状態レジスタ (同期)
    // ============================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_RESET_LO;
        else
            state <= next_state;
    end

    // ============================================================
    //  次状態ロジック (組合せ)
    //  実装済: リセット/割込チェック/フェッチ/NOP/HALT
    //         + 第1段(2Bレジスタ ALU/MOV/CMP: EXEC_ALU→WRITEBACK)
    //  未実装: imm系/分岐/メモリ/スタック/EXT/制御/割込受理 → S_HALT退避
    // ============================================================
    always_comb begin
        next_state = state;
        case (state)
            // --- リセットベクタ読み(2byte) ---
            S_RESET_LO: begin
                if (mem_ready) next_state = S_RESET_HI;
            end
            S_RESET_HI: begin
                if (mem_ready) next_state = S_IRQCHK;
            end
            // --- 割込チェック ---
            S_IRQCHK: begin
                if (irq_pending != 3'd0 && flags_ie)
                    next_state = S_IRQ_ACCEPT;
                else
                    next_state = S_FETCH;
            end
            // --- opcodeフェッチ ---
            S_FETCH: begin
                if (mem_ready) next_state = S_OPFETCH;
            end
            // --- opcode確定後の分岐(命令長判定) ---
            //  第1段スコープ: 1バイト命令(NOP/HALT) + 2バイトALU/MOV/CMP。
            //  imm要/EXT/メモリ/分岐/スタック/制御は順次肉付け(次段)。
            S_OPFETCH: begin
                if (need_rb) begin
                    // rbフェッチ中: mem_ready 待ちで滞留、確定後に実行状態へ
                    if (mem_ready) begin
                        case (dec_idec)
                            // 2バイト レジスタALU/MOV/CMP → ALU実行
                            ID_MOV, ID_ADD, ID_SUB, ID_CMP,
                            ID_AND, ID_OR,  ID_XOR, ID_NOT,
                            ID_SHL, ID_SHR, ID_SAR:
                                next_state = S_EXEC_ALU;
                            // 4バイト 即値ALU/LDWI/CMPI → imm16フェッチへ
                            ID_LDWI, ID_ADDI, ID_SUBI, ID_CMPI,
                            ID_ANDI, ID_ORI,  ID_XORI:
                                next_state = S_IMML;
                            // 2バイト メモリ [rS]/[rD] → S_DECODE(アドレス確定)経由
                            ID_LDW_RS, ID_STW_RD:
                                next_state = S_DECODE;
                            // 4バイト メモリ [imm16]/[X+imm16] → imm16フェッチへ
                            ID_LDW_ABS, ID_STW_ABS,
                            ID_LDW_XI,  ID_STW_XI:
                                next_state = S_IMML;
                            // その他は次段。安全停止。
                            default:
                                next_state = S_HALT;
                        endcase
                    end
                    // mem_ready==0 の間は state 保持(滞留)
                end else if (dec_need_subop) begin
                    // EXT命令(0x1F): opcode確定済、サブopフェッチへ
                    next_state = S_SUBOP;
                end else begin
                    // rb不要命令(1バイト命令 / 3バイト分岐)
                    case (dec_idec)
                        ID_NOP:  next_state = S_IRQCHK;  // 1バイト・副作用なし
                        ID_HALT: next_state = S_HALT;    // 停止
                        // 【第5-1段】制御命令(1バイト, EXT非経由)
                        //  EI/DI: FLAGS.IE操作のみ→S_IRQCHK直行(PCはS_FETCHで+1済)。
                        ID_EI, ID_DI: next_state = S_IRQCHK;
                        //  SYSCALL: irq_pending←4セットのみ(スタック操作なし)。
                        //   受理は次のS_IRQCHK→S_IRQ_ACCEPT(第5-3段)で発火。
                        ID_SYSCALL:   next_state = S_EXEC_SYSCALL;
                        // 3バイト分岐(JMP/Bcc): imm16(=rel16)フェッチへ
                        ID_JMP, ID_BEQ, ID_BNE, ID_BLT, ID_BGE:
                                 next_state = S_IMML;
                        // 【第5-2段】JSR(3バイト, 絶対imm16): imm16(=target)フェッチへ。
                        //  imm確定後S_IMMHでS_EXEC_JSRへ分岐(下記)。
                        ID_JSR:  next_state = S_IMML;
                        // 【第5-2段】RET(1バイト): pop→PC。S_EXEC_RETでctx設定しpopへ。
                        ID_RET:  next_state = S_EXEC_RET;
                        // 【第5-3段】IRET(1バイト): pop2回(FLAGS→PC)。
                        //  S_EXEC_IRETでctx=CTX_IRET/pop_count=2設定しpop機構へ。
                        ID_IRET: next_state = S_EXEC_IRET;
                        default: next_state = S_HALT;    // 次段で拡張
                    endcase
                end
            end
            // --- EXT サブopフェッチ(0x1F命令の2バイト目) ---
            //  mem[PC]→subop_r, PC+1, subop_valid=1(下記ff/regfileで実施)。
            //  【案U】次状態は固定 S_DECODE。subop_r は次エッジでラッチされるため
            //  この時点で dec_idec は未確定(ID_ILLEGAL)。判定は subop確定後の
            //  S_DECODE で行う(第1段で経験した1サイクル遅延と同型の回避)。
            S_SUBOP: begin
                if (mem_ready) next_state = S_DECODE;
            end
            // --- imm16フェッチ(下位→上位、各1サイクル PC+1) ---
            //  即値ALU/LDWI/CMPI用。フェッチ後 S_EXEC_ALU に合流
            //  (operand_b選択でimm/rSを切替、実行状態を簡素化)。
            S_IMML: begin
                if (mem_ready) next_state = S_IMMH;
            end
            S_IMMH: begin
                if (mem_ready) begin
                    if (dec_idec == ID_JSR)     next_state = S_EXEC_JSR;   // 【第5-2段】JSR: target確定→push機構へ
                    else if (dec_is_branch)     next_state = S_EXEC_BRANCH; // JMP/Bcc
                    else if (is_mem_word)       next_state = S_DECODE;      // LDW/STW: アドレス確定へ
                    // バイトメモリ[imm16](LDB/STB): アライメント不要→直行
                    //  addr_r←imm_r は下記regfileでラッチ。
                    else if (dec_mem_op == 2'b01 && ~dec_mem_w16)
                                                next_state = S_MEMR8;      // LDB[imm16]
                    else if (dec_mem_op == 2'b10 && ~dec_mem_w16)
                                                next_state = S_MEMW8;      // STB[imm16]
                    else                        next_state = S_EXEC_ALU;    // 即値ALU/LDWI/CMPI
                end
            end
            // --- 命令種別分岐＆アドレス確定 (案X:ワード / 案U:バイト 合流) ---
            //  この時点で subop_valid/imm_r/rf_rdata 確定。
            //  ワード(mem_w16=1): アライメント判定→S_MEMR_LO/S_MEMW_LO(2アクセス)
            //  バイト(mem_w16=0, EXT由来):
            //    [X](2B, is_imm16=0)   : アドレス=X, アライメント不要→S_MEMR8/S_MEMW8
            //    [imm](4B, is_imm16=1) : imm未フェッチ→S_IMML(フェッチ後S_IMMHで直行)
            S_DECODE: begin
                // 【第5-1段】PUSH/POP(EXT subop 0x00-05)を最優先分岐。
                //  メモリ命令信号(mem_w16/mem_op)に依存せずidecで振分け→誤入防止。
                if (dec_idec == ID_PUSH) begin
                    next_state = S_PUSH_LO;         // push下位byteへ
                end else if (dec_idec == ID_POP) begin
                    next_state = S_POP_LO;          // pop下位byteへ
                end else if (dec_mem_w16) begin
                    // ワード(LDW/STW): 第4-A段。アライメント判定あり。
                    if (mem_misaligned)   next_state = S_IRQCHK;   // アライメント例外
                    else if (is_mem_load) next_state = S_MEMR_LO;
                    else                  next_state = S_MEMW_LO;  // is_mem_store
                end else begin
                    // バイト(LDB/STB): アライメント例外なし(rd8/wr8実照合)。
                    if (dec_is_imm16) begin
                        next_state = S_IMML;  // [imm16]: imm フェッチへ
                    end else begin
                        // [X]: アドレス=rf_x(下記regfileでaddr_rラッチ)
                        if (dec_mem_op == 2'b01) next_state = S_MEMR8; // LDB
                        else                     next_state = S_MEMW8; // STB
                    end
                end
            end
            // --- 分岐実行(相対rel16: 分岐先=次命令アドレス+off、条件成立時のみ) ---
            S_EXEC_BRANCH: begin
                next_state = S_IRQCHK; // PC更新は下記regfile制御で実施
            end
            // --- レジスタ/即値ALU/MOV/CMP実行(ALUは組合せ、ここで結果確定) ---
            S_EXEC_ALU: begin
                next_state = S_WRITEBACK;
            end
            // --- 書き戻し(rD更新+フラグ更新)→次命令 ---
            S_WRITEBACK: begin
                next_state = S_IRQCHK;
            end
            // --- メモリ ワードリード(LE: LO=mem[addr], HI=mem[addr+1]) ---
            S_MEMR_LO: begin
                if (mem_ready) next_state = S_MEMR_HI;
            end
            S_MEMR_HI: begin
                // 【第5-3段(b)】ベクタ読み(CTX_IRQVEC)完了はPC←vecしてS_FETCHへ。
                //  通常ロードと区別(戻り先を取り違えると受理後PCが飛ばない)。
                if (mem_ready) begin
                    if (stack_ctx == CTX_IRQVEC)
                        next_state = S_FETCH;      // 割込受理: ベクタ→PC(regfile側)→命令フェッチ
                    else
                        next_state = S_WRITEBACK;  // 通常ロード: rD←{hi,lo}, set_zn
                end
            end
            // --- メモリ ワードライト(LE: LO=mem[addr], HI=mem[addr+1]) ---
            S_MEMW_LO: begin
                if (mem_ready) next_state = S_MEMW_HI;
            end
            S_MEMW_HI: begin
                if (mem_ready) next_state = S_IRQCHK;    // ストアはフラグ不変
            end
            // --- バイト リード(LDB): 1バイト読→A/B へゼロ拡張, フラグ不変 ---
            S_MEMR8: begin
                if (mem_ready) next_state = S_IRQCHK;    // 書込は下記regfileで
            end
            // --- バイト ライト(STB): 1バイト書, フラグ不変 ---
            S_MEMW8: begin
                if (mem_ready) next_state = S_IRQCHK;
            end
            // ================= 【第5-1段】制御・スタック =================
            // --- SYSCALL: irq_pending←4セット(下記ffで)→S_IRQCHK ---
            //  スタック操作なし。受理は次S_IRQCHK→S_IRQ_ACCEPT(第5-3段)。
            S_EXEC_SYSCALL: begin
                next_state = S_IRQCHK;
            end
            // --- PUSH(pre-decrement, LE 8bit2アクセス) ---
            //  書込先=SP-2(新SP)。LO=mem[SP-2]=下位, HI=mem[SP-1]=上位。
            //  SP確定(SP←SP-2)はS_PUSH_HI完了時ワンショット(下記regfile)。
            S_PUSH_LO: begin
                if (mem_ready) next_state = S_PUSH_HI;
            end
            S_PUSH_HI: begin
                if (mem_ready) begin
                    // 【第5-3段(b)】割込受理のpush2回制御(C-2: push_count現在値で分岐)。
                    //  1回目(push_count=2, PC push)→継続S_PUSH_LO(FLAGS push)。
                    //  2回目(push_count=1, FLAGS push)→S_MEMR_LO(ベクタ読み)。
                    if (stack_ctx == CTX_IRQ && push_count > 2'd1)
                        next_state = S_PUSH_LO;    // 割込受理: FLAGS pushへ継続
                    else if (stack_ctx == CTX_IRQ)
                        next_state = S_MEMR_LO;     // 割込受理: ベクタ読みへ
                    else
                        next_state = S_IRQCHK;      // PUSH/JSR(単発)は従来通り
                end
            end
            // --- POP(post-increment, LE 8bit2アクセス) ---
            //  読込元=SP(現SP)。LO=mem[SP]=下位, HI=mem[SP+1]=上位。
            //  対象reg書戻し+SP←SP+2はS_POP_HI完了時ワンショット(下記regfile/ff)。
            S_POP_LO: begin
                if (mem_ready) next_state = S_POP_HI;
            end
            // 【第5-3段】POP完了の遷移: pop_countで多重pop制御(C-2: ff出力を分岐条件)。
            //  pop_count>1(まだ続く=IRET1回目)→S_POP_LOへ戻る、==1(最後)→S_IRQCHK。
            //  第5-1/5-2段(POP/RET)はpop_count=1固定なので従来通りS_IRQCHKへ。
            S_POP_HI: begin
                if (mem_ready) begin
                    if (pop_count > 2'd1) next_state = S_POP_LO;  // 継続(IRET FLAGS→PC)
                    else                  next_state = S_IRQCHK;  // 最後
                end
            end
            // ================= 【第5-2段】JSR/RET =================
            // --- JSR: target確定済(imm_r)。戻り先PC(rf_pc)をpush後 PC←target。 ---
            //  S_EXEC_JSRで push_src←rf_pc, stack_ctx←CTX_JSR(下記ff)→push機構。
            //  push完了(S_PUSH_HI, ctx=JSR)で PC←imm_r(下記regfile)。
            S_EXEC_JSR: begin
                next_state = S_PUSH_LO;
            end
            // --- RET: pop→PC。S_EXEC_RETで stack_ctx←CTX_RET(下記ff)→pop機構。 ---
            //  pop完了(S_POP_HI, ctx=RET)で PC←{hi,lo}(下記regfile)。
            S_EXEC_RET: begin
                next_state = S_POP_LO;
            end
            // ================= 【第5-3段】IRET =================
            // --- IRET: pop2回(FLAGS先→PC後)。S_EXEC_IRETでctx=CTX_IRET/pop_count=2
            //  設定(下記ff)→pop機構へ。pop完了はS_POP_HIでpop_count分岐。
            S_EXEC_IRET: begin
                next_state = S_POP_LO;
            end
            // ============= 【第5-3段(b)】割込受理 =============
            // --- S_IRQ_ACCEPT: 受理開始。ff側でirq_latch/ctx/push_count/push_src
            //  を設定→push機構(1回目=PC)へ。push2回(PC→FLAGS)後ベクタ読み。
            S_IRQ_ACCEPT: begin
                next_state = S_PUSH_LO;
            end
            S_HALT: begin
                next_state = S_HALT;
            end
            default: begin
                next_state = S_HALT;
            end
        endcase
    end

    // ============================================================
    //  バス出力 (状態別アドレス出し分け)
    // ============================================================
    always_comb begin
        mem_addr  = rf_pc;      // default
        mem_wdata = 8'h00;
        mem_rd    = 1'b0;
        mem_wr    = 1'b0;
        case (state)
            S_RESET_LO: begin mem_addr = 16'h0000; mem_rd = 1'b1; end
            S_RESET_HI: begin mem_addr = 16'h0001; mem_rd = 1'b1; end
            S_FETCH:    begin mem_addr = rf_pc;    mem_rd = 1'b1; end
            // 【バグ修正・2026-07-11・V3統合時に発覚】EXTサブopcodeフェッチ。
            //  従来この case が欠落しており mem_rd が立たないままだった。
            //  regfile制御(S_SUBOP時 rf_we_pc, 934行目付近)とsubop_rラッチ
            //  (1098行目付近)は mem_ready 条件を持つため、ideal memory
            //  (mem_ready固定1)のV1/V2 TBでは結果に影響せず見過ごされた。
            //  V3(CDCブリッジ+PSRAM、実req/ack型)で mem_rd=0 のため
            //  mem_ready が永久に返らずハングすることで発覚(KY34)。
            S_SUBOP:    begin mem_addr = rf_pc;    mem_rd = 1'b1; end
            // rb要命令のみ mem[PC] を rb として読む(NOP等はスキップ)
            S_OPFETCH:  begin
                if (need_rb) begin mem_addr = rf_pc; mem_rd = 1'b1; end
            end
            // imm16フェッチ: mem[PC]から下位/上位を各1バイト読む
            S_IMML:     begin mem_addr = rf_pc; mem_rd = 1'b1; end
            S_IMMH:     begin mem_addr = rf_pc; mem_rd = 1'b1; end
            // メモリ ワードリード (LE: LO=addr, HI=addr+1)
            //  【第5-3段(b)】CTX_IRQVEC(割込ベクタ読み)時はaddr=irq_vec_addr(=irq_latch*2)。
            S_MEMR_LO:  begin mem_addr = addr_r;         mem_rd = 1'b1; end
            S_MEMR_HI:  begin mem_addr = addr_r + 16'd1; mem_rd = 1'b1; end
            // メモリ ワードライト (LE: LO=下位byte, HI=上位byte)
            S_MEMW_LO:  begin mem_addr = addr_r;         mem_wdata = store_lo; mem_wr = 1'b1; end
            S_MEMW_HI:  begin mem_addr = addr_r + 16'd1; mem_wdata = store_hi; mem_wr = 1'b1; end
            // バイト リード/ライト (単一バイト・アライメント不要)
            S_MEMR8:    begin mem_addr = addr_r; mem_rd = 1'b1; end
            S_MEMW8:    begin mem_addr = addr_r; mem_wdata = byte_store_data; mem_wr = 1'b1; end
            // 【第5-1段】PUSH(pre-dec, LE): mem[SP-2]=下位, mem[SP-1]=上位。
            S_PUSH_LO:  begin mem_addr = sp_m2; mem_wdata = stk_push_lo; mem_wr = 1'b1; end
            S_PUSH_HI:  begin mem_addr = sp_m1; mem_wdata = stk_push_hi; mem_wr = 1'b1; end
            // 【第5-1段】POP(post-inc, LE): mem[SP]=下位, mem[SP+1]=上位。
            S_POP_LO:   begin mem_addr = rf_sp; mem_rd = 1'b1; end
            S_POP_HI:   begin mem_addr = sp_p1; mem_rd = 1'b1; end
            default: ; // 他状態は次段で肉付け
        endcase
    end

    // ============================================================
    //  観測出力
    // ============================================================
    always_comb begin
        dbg_pc    = rf_pc;
        dbg_a     = rf_a;
        dbg_b     = rf_b;
        dbg_x     = rf_x;
        dbg_sp    = rf_sp;
        dbg_flags = rf_flags;
        dbg_halt  = (state == S_HALT);
        dbg_irq_pending = irq_pending;
    end

    // ============================================================
    //  ★案0-a' (v5_irq0_ack_design_v0_1): irq0_ack 生成★
    //   β点=ベクタ読み完了(受理が後戻りしない確定点)で1クロックパルス。
    //   emu23 の「受理で発火チケット消費(irq_pending=-1)」を写像する。
    //   ・独立 assign。既存 ff/comb ブロックには一切触れない(§4.3/§5-2)。
    //   ・irq_latch==3'd1 ガードで timer 受理のみ抽出。
    //     device(2)/align(3)/syscall(4) 受理では立たない → UART無影響。
    // ============================================================
    assign irq0_ack = (state == S_MEMR_HI) && mem_ready
                      && (stack_ctx == CTX_IRQVEC) && (irq_latch == 3'd1);

    // ============================================================
    //  レジスタファイル制御 (状態別)
    //  【本日KY核心】PC/SP更新は「state==X && mem_ready」の遷移確定
    //   サイクルでのみパルス。滞留中(mem_ready==0)は加算しない。
    // ============================================================
    always_comb begin
        rf_raddr_d = rb_rd;
        rf_raddr_s = rb_rs;
        rf_we_gp    = 1'b0;
        rf_waddr_gp = rb_rd;
        rf_wdata_gp = alu_result;
        rf_we_pc    = 1'b0;
        rf_wdata_pc = 16'h0000;
        rf_we_sp    = 1'b0;
        rf_wdata_sp = 16'h0000;
        rf_we_flags = 1'b0;
        rf_wdata_flags = 16'h0000;

        case (state)
            // リセットベクタ上位取得時: PC←{hi,lo}, SP←0
            S_RESET_HI: begin
                if (mem_ready) begin
                    rf_we_pc    = 1'b1;
                    rf_wdata_pc = {mem_rdata, byte_lo}; // {hi,lo}
                    rf_we_sp    = 1'b1;
                    rf_wdata_sp = 16'h0000;
                end
            end
            // opcodeフェッチ完了時: PC+1 (ワンショット)
            S_FETCH: begin
                if (mem_ready) begin
                    rf_we_pc    = 1'b1;
                    rf_wdata_pc = rf_pc + 16'd1;
                end
            end
            // rbフェッチ完了時: PC+1 (rb要命令のみ、mem_readyワンショット)
            S_OPFETCH: begin
                if (need_rb && mem_ready) begin
                    rf_we_pc    = 1'b1;
                    rf_wdata_pc = rf_pc + 16'd1;
                end
                // 【第5-1段】EI/DI: FLAGS.IE(bit7) set/clr。
                //  1バイト命令(need_rb=0)。PCはS_FETCHで+1済のためここでは触らない。
                //  dec_ie_set/clrはopcode確定時に確定。他ビットは保持(set_znと同思想)。
                //  【v0.5.6修正】IE=bit7。旧 {1'b1,flags_lo15} は 1'b1 が bit15 に載り
                //   IE(bit7)を操作していなかった(EIが効かない真因)。bit7のみ差替え・
                //   他15bit保持の正しい合成に訂正。
                if (dec_ie_set) begin
                    rf_we_flags    = 1'b1;
                    rf_wdata_flags = {flags_ie_hi, 1'b1, flags_ie_lo};  // IE(bit7)←1
                end else if (dec_ie_clr) begin
                    rf_we_flags    = 1'b1;
                    rf_wdata_flags = {flags_ie_hi, 1'b0, flags_ie_lo};  // IE(bit7)←0
                end
            end
            // imm16フェッチ完了時: 各バイトで PC+1 (計+2)
            S_IMML: begin
                if (mem_ready) begin
                    rf_we_pc    = 1'b1;
                    rf_wdata_pc = rf_pc + 16'd1;
                end
            end
            S_IMMH: begin
                if (mem_ready) begin
                    rf_we_pc    = 1'b1;
                    rf_wdata_pc = rf_pc + 16'd1;
                end
            end
            // EXTサブopフェッチ完了時: PC+1
            S_SUBOP: begin
                if (mem_ready) begin
                    rf_we_pc    = 1'b1;
                    rf_wdata_pc = rf_pc + 16'd1;
                end
            end
            // 書き戻し: reg_we なら rD←ALU結果、flag_we なら Z/N 更新。
            //  MOV=reg_we1/flag_we0(フラグ不変)、CMP=reg_we0/flag_we1、
            //  ALU演算=reg_we1/flag_we1。全てデコーダ信号に従う。
            //  【論点A】メモリロード(is_mem_load)時は rD←load_data, set_zn。
            //   データ源をALU系/メモリ系で選択(状態は共用、可読性より状態数抑制)。
            S_WRITEBACK: begin
                if (is_mem_load) begin
                    // LDW: rD←ロード値, Z/N更新(実照合: set_zn)
                    rf_we_gp       = 1'b1;
                    rf_waddr_gp    = rb_rd;
                    rf_wdata_gp    = load_data;
                    rf_we_flags    = 1'b1;
                    rf_wdata_flags = {flags_hi, load_n, load_z};
                end else begin
                    if (dec_reg_we) begin
                        rf_we_gp    = 1'b1;
                        rf_waddr_gp = rb_rd;
                        rf_wdata_gp = alu_result;
                    end
                    if (dec_flag_we) begin
                        rf_we_flags    = 1'b1;
                        // Z=bit0, N=bit1, 他ビットは現FLAGS保持(set_zn相当)
                        rf_wdata_flags = {flags_hi, alu_n, alu_z};
                    end
                end
            end
            // 【第4-B段・論点C(b)】バイトロード(LDB)専用書戻し。
            //  S_MEMR8完了で対象レジスタ(A/B)←ゼロ拡張(mem8)。フラグ不変(触らない)。
            //  A/B選択は byte_reg_is_b(=subop_r[1])。S_WRITEBACK共用せず責務分離。
            S_MEMR8: begin
                if (mem_ready) begin
                    rf_we_gp    = 1'b1;
                    rf_waddr_gp = byte_reg_is_b ? 4'd1 : 4'd0; // 1=B, 0=A
                    rf_wdata_gp = {8'h00, mem_rdata};          // ゼロ拡張
                    // flag更新なし(LDBはFLAGS不変)
                end
            end
            // 分岐実行(相対): 成立時 PC ← (次命令アドレス) + off。
            //  S_IMMHでPC+2済 = rf_pc は既に次命令アドレス。
            //  imm_r を符号付off として加算(16bit wrap = (uint16_t)(pc+off)一致)。
            //  不成立時は rf_pc(次命令)のまま = PC更新しない。
            S_EXEC_BRANCH: begin
                if (branch_taken) begin
                    rf_we_pc    = 1'b1;
                    rf_wdata_pc = rf_pc + imm_r; // off=imm_r(2の補数)
                end
            end
            // 【第5-1/5-2段】PUSH完了: SP←SP-2(pre-dec確定・ワンショット)。
            //  上位byte書込(S_PUSH_HI)がmem_readyになった遷移確定サイクルでSP確定。
            //  滞留中(mem_ready=0)はrf_sp不変=書込アドレス安定(7/01 KY遵守)。
            //  【第5-2段】CTX_JSR時: 同サイクルで PC←imm_r(target)。emu23順序
            //   (push16(pc)後 pc=target)と外部観測等価。
            S_PUSH_HI: begin
                if (mem_ready) begin
                    rf_we_sp    = 1'b1;
                    rf_wdata_sp = sp_m2;   // SP-2
                    if (stack_ctx == CTX_JSR) begin
                        rf_we_pc    = 1'b1;
                        rf_wdata_pc = imm_r; // PC←target(絶対)
                    end
                    // 【第5-3段(b)】割込受理: 2回目push(FLAGS)完了でIE=0(D-1: push後)。
                    //  push_count==1が2回目(FLAGS)push完了。1回目(PC,==2)ではクリアしない。
                    //  bit7(IE)のみ0、他FLAGSビットは保持(現値&16'hFF7F)。
                    if (stack_ctx == CTX_IRQ && push_count == 2'd1) begin
                        rf_we_flags    = 1'b1;
                        rf_wdata_flags = rf_flags & 16'hFF7F; // IE=bit7 クリア
                    end
                end
            end
            // 【第5-1/5-2/5-3段】POP完了: SP←SP+2(post-inc確定)。書戻し先をctxで分岐。
            //  下位はmem_loにラッチ済(下記ff)、上位は今サイクルのmem_rdata。
            //  CTX_POP: 対象reg(A/B/X)←{hi,lo}。CTX_RET: PC←{hi,lo}。
            //  CTX_IRET: pop_count==2(1回目)→FLAGS←{8'h00,mem_lo}(下位8bit,D-2承認)、
            //            pop_count==1(2回目)→PC←{hi,lo}。
            S_POP_HI: begin
                if (mem_ready) begin
                    rf_we_sp    = 1'b1;
                    rf_wdata_sp = rf_sp + 16'd2;       // SP+2(共通)
                    if (stack_ctx == CTX_IRET) begin
                        if (pop_count == 2'd2) begin
                            // IRET 1回目: FLAGS←pop値の下位8bitのみ(上位0クリア)
                            rf_we_flags    = 1'b1;
                            rf_wdata_flags = {8'h00, mem_lo};
                        end else begin
                            // IRET 2回目: PC←pop値
                            rf_we_pc    = 1'b1;
                            rf_wdata_pc = {mem_rdata, mem_lo};
                        end
                    end else if (stack_ctx == CTX_RET) begin
                        rf_we_pc    = 1'b1;
                        rf_wdata_pc = {mem_rdata, mem_lo}; // PC←pop値
                    end else begin
                        // CTX_POP: 対象reg書戻し。FLAGS不変(POPはZ/N更新しない・実照合)
                        rf_we_gp    = 1'b1;
                        rf_waddr_gp = stk_pop_waddr;       // A/B/X
                        rf_wdata_gp = {mem_rdata, mem_lo}; // LE合成
                    end
                end
            end
            // 【第5-3段(b)】割込ベクタ読み完了: PC←vec(mem[irq_latch*2] 16bit LE)。
            //  CTX_IRQVEC限定(通常ロードはS_WRITEBACK処理でここに来ない/ガードで無影響)。
            //  下位=mem_lo(S_MEMR_LOでラッチ済), 上位=今サイクルmem_rdata。→S_FETCHへ。
            S_MEMR_HI: begin
                if (mem_ready && stack_ctx == CTX_IRQVEC) begin
                    rf_we_pc    = 1'b1;
                    rf_wdata_pc = {mem_rdata, mem_lo}; // PC←ベクタ値
                end
            end
            default: ; // 他状態は次段で肉付け
        endcase
    end

    // ALU入力 (第1段レジスタ + 第2段即値)
    //  operand_a = rD現在値(rf_rdata_d)
    //  operand_b = 即値命令なら imm_r、レジスタ命令なら rS現在値(rf_rdata_s)
    //  alu_op    = idecから変換(alu_op_dec)。MOV/LDWI=PASSB, CMP/CMPI=SUB。
    //  ※S_EXEC_ALUに到達するのはレジスタ/即値ALU系のみ(メモリ/分岐は非到達)
    //    のため dec_is_imm16 での切替で足りる。
    always_comb begin
        alu_op = alu_op_dec;
        alu_a  = rf_rdata_d;
        alu_b  = dec_is_imm16 ? imm_r : rf_rdata_s;
    end

    // 内部ラッチ更新 (スケルトン: irq_pending のみ最小)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ir       <= 8'h00;
            subop_r  <= 8'h00;
            subop_valid <= 1'b0;
            rb_r     <= 8'h00;
            imm_r    <= 16'h0000;
            addr_r   <= 16'h0000;
            byte_lo  <= 8'h00;
            mem_lo   <= 8'h00;
            load_data <= 16'h0000;
            irq_pending <= 3'd0;
            stack_ctx   <= CTX_NONE;
            push_src    <= 16'h0000;
            pop_count   <= 2'd0;
            push_count  <= 2'd0;
            irq_latch   <= 3'd0;
        end else begin
            // リセットベクタ下位byteラッチ
            if (state == S_RESET_LO && mem_ready)
                byte_lo <= mem_rdata;
            // opcodeラッチ + PC前進は regfile側(we_pc)で実施
            if (state == S_FETCH && mem_ready)
                ir <= mem_rdata;
            // rbラッチ (rb要命令のフェッチ完了時)
            if (state == S_OPFETCH && need_rb && mem_ready)
                rb_r <= mem_rdata;
            // imm16ラッチ: 下位byte→byte_lo、上位byte到着で {hi,lo}→imm_r
            if (state == S_IMML && mem_ready)
                byte_lo <= mem_rdata;
            if (state == S_IMMH && mem_ready)
                imm_r <= {mem_rdata, byte_lo};
            // 【第4-B段】EXTサブopラッチ + 確定フラグセット + subop命令のPC進行。
            if (state == S_SUBOP && mem_ready) begin
                subop_r     <= mem_rdata;
                subop_valid <= 1'b1;
            end
            // subop_valid クリア: 命令完了(S_IRQCHK)で次命令に持ち越さない。
            if (state == S_IRQCHK)
                subop_valid <= 1'b0;
            // 【第4-B段】バイト[imm16]直行時: S_IMMHで addr_r←imm値を直接ラッチ。
            //  (S_DECODEを経由しないため。imm_rと同一値 {hi,lo}。)
            if (state == S_IMMH && mem_ready && ~dec_mem_w16 &&
                (dec_mem_op == 2'b01 || dec_mem_op == 2'b10))
                addr_r <= {mem_rdata, byte_lo};
            // 【第4-A段】アドレス確定(案X): S_DECODEで実効アドレスをラッチ。
            //  eff_addrはこの時点で確定(2B:rf_rdata, 4B:imm_r確定後)。
            if (state == S_DECODE)
                addr_r <= eff_addr;
            // アライメント例外: S_DECODEで奇数アドレス検出→irq_pending←3(align)。
            //  受理シーケンスは第5段(S_IRQ_ACCEPT)で実装。
            if (state == S_DECODE && mem_misaligned)
                irq_pending <= 3'd3;
            // メモリ ワードリード: LO下位byte→mem_lo, HI上位byte到着で load_data確定
            if (state == S_MEMR_LO && mem_ready)
                mem_lo <= mem_rdata;
            if (state == S_MEMR_HI && mem_ready)
                load_data <= {mem_rdata, mem_lo};
            // 【第5-1段】POP下位byteラッチ(mem_lo流用): S_POP_LO完了で下位を保持。
            //  S_POP_HIで {mem_rdata(上位), mem_lo(下位)} を対象regへ書戻し(regfile)。
            if (state == S_POP_LO && mem_ready)
                mem_lo <= mem_rdata;
            // 【第5-1段】SYSCALL: irq_pending←4(実照合L1225-1231)。スタック操作なし。
            //  受理は次のS_IRQCHK→S_IRQ_ACCEPT(第5-3段)で発火。
            if (state == S_EXEC_SYSCALL)
                irq_pending <= 3'd4;
            // 【第5-2段】stack_ctx設定(共通push/pop機構の戻り先分岐用)。
            //  PUSH/POP: S_DECODEで確定(idecはsubop_valid後)。
            if (state == S_DECODE && dec_idec == ID_PUSH)
                stack_ctx <= CTX_PUSH;
            if (state == S_DECODE && dec_idec == ID_POP)
                stack_ctx <= CTX_POP;
            //  JSR: 戻り先PC(rf_pc, imm16フェッチ後=次命令)をpush_srcへ, ctx=CTX_JSR。
            if (state == S_EXEC_JSR) begin
                stack_ctx <= CTX_JSR;
                push_src  <= rf_pc;   // S_IMMHでPC+2済=JSR命令の次命令アドレス
            end
            //  RET: ctx=CTX_RET(pop→PC)。
            if (state == S_EXEC_RET)
                stack_ctx <= CTX_RET;
            // 【第5-3段】IRET: ctx=CTX_IRET, pop_count←2(FLAGS→PCの2回pop)。
            if (state == S_EXEC_IRET) begin
                stack_ctx <= CTX_IRET;
                pop_count <= 2'd2;
            end
            // 【第5-3段(b)】割込受理 入口(S_IRQ_ACCEPT):
            //  ・irq_latch←irq_pending: 受理中のirq番号を退避(C-1)。以降ベクタ
            //    計算はirq_latchのみ参照。irq_pendingへの新irq_inは競合しても無害。
            //  ・stack_ctx←CTX_IRQ, push_count←2(PC/FLAGSの2回push)。
            //  ・push_src←rf_pc: 1回目pushはPC(戻り先)。emu23: push16(pc)先。
            if (state == S_IRQ_ACCEPT) begin
                irq_latch  <= irq_pending;
                stack_ctx  <= CTX_IRQ;
                push_count <= 2'd2;
                push_src   <= rf_pc;
                // 【案1】ベクタアドレスをaddr_rにラッチ(組合せ選択を排しループ回避)。
                //  vec = irq_pending*2 (mem[2/4/6/8])。この時点のirq_pendingは受理確定値
                //  (クリア前)なのでirq_latch非経由で直接確定。以降S_MEMR_LO/HIはaddr_r参照。
                addr_r     <= {12'd0, irq_pending, 1'b0}; // irq_pending<<1
            end
            // 【第5-3段(b)】割込受理 push_count減算 + push_src2段セット + IEクリア:
            //  S_PUSH_HI完了ワンショット(SP更新と同期・C-2)。CTX_IRQ時のみ。
            //  1回目(push_count=2, PC push完了): →push_count=1, push_src←rf_flags
            //    (2回目pushデータ=FLAGS)。IEはまだクリアしない(D-1)。
            //  2回目(push_count=1, FLAGS push完了): →push_count=0, stack_ctx←CTX_IRQVEC
            //    (ベクタ読みへ), IE=0(flags更新, push後=D-1)。
            if (state == S_PUSH_HI && mem_ready && stack_ctx == CTX_IRQ) begin
                push_count <= push_count - 2'd1;
                if (push_count > 2'd1)
                    push_src <= rf_flags;      // 1回目完了: 次push=FLAGS
                else
                    stack_ctx <= CTX_IRQVEC;   // 2回目完了: ベクタ読みへ
            end
            // 【第5-3段】pop_count設定(単発pop=1): POP(S_DECODE)/RET(S_EXEC_RET)。
            //  これによりS_POP_HIの遷移分岐(pop_count>1)が単発popで正しく最後扱い。
            if (state == S_DECODE && dec_idec == ID_POP)
                pop_count <= 2'd1;
            if (state == S_EXEC_RET)
                pop_count <= 2'd1;
            // 【第5-3段】pop_count減算: S_POP_HI完了ワンショット(SP更新と同期・C-2)。
            //  滞留中(mem_ready=0)は減算しない(7/01 KY)。IRET多重popの周回制御。
            if (state == S_POP_HI && mem_ready && pop_count != 2'd0)
                pop_count <= pop_count - 2'd1;
            //  命令完了でctxクリア(次命令へ持ち越さない, subop_validと同思想)。
            if (state == S_IRQCHK)
                stack_ctx <= CTX_NONE;
            // 【第5-3段(b)】割込ベクタ読み完了(CTX_IRQVEC): 受理シーケンス終了処理。
            //  irq_pending←0(受理済クリア), stack_ctx←CTX_NONE(即クリア: S_FETCH経由で
            //  CTX_IRQVEC残留を防止)。PC←vecはregfile側で実施済。→S_FETCHでハンドラ起動。
            if (state == S_MEMR_HI && mem_ready && stack_ctx == CTX_IRQVEC) begin
                irq_pending <= 3'd0;
                stack_ctx   <= CTX_NONE;
            end
            // 【V5/S5・第1段 pending 保護】割込取り込み(S_IRQCHKで外部要求をラッチ)
            //  ★irq_pending が【空(=0)の時だけ】受け付ける★
            //  根拠: emu23_v110.c L1591 `if (cpu.irq_pending < 0 && YSD8002_tick(...))`
            //        = 受理待ちが在るなら新規要求で上書きしない(取りこぼし/横取り防止)。
            //  ★flags_ie を条件に含めてはならない★
            //        emu23 の pending ラッチは IE を見ない(IE を見るのは【受理】側=L1214)。
            //        ラッチ段で IE を見ると、DI 区間の要求が消滅し emu23 と非等価になる。
            if (state == S_IRQCHK && irq_in != 3'd0 && irq_pending == 3'd0)
                irq_pending <= irq_in;
        end
    end

endmodule
