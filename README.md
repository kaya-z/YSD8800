# YSD8800

オリジナル16bit CPU YSD8800のページへようこそ。

YUI OS（YSD8800上で動く自作マイクロカーネルOS）、および対応するツールチェーン（アセンブラ・リンカ・Cコンパイラ・Forthクロスコンパイラ・エミュレータ）とFPGA実装（SystemVerilog RTL）を開発しています。

最新の版数管理は `docs/reference/` の下の各台帳に記録があります。

- 文書一覧: `design_inventory_vxx.docx`
- RTLソース一覧: `fpga_source_version_ledger_vxx.md`
- ツール一覧: `tool_version_ledger_vxxx.md`

## ディレクトリ構成

```
YSD8800/
├── docs/                設計書・レビュー・引継ぎメモ
│   ├── architecture/    ISA仕様・ABI・MMU仕様など、版に依らない基本設計
│   ├── os/               YUI OS 設計書
│   ├── toolchain/        アセンブラ・リンカ・Cコンパイラ・Force・エミュレータの設計書
│   ├── fpga/             FPGA実装（RTL）の設計書・工程メモ
│   ├── reviews/          各設計書に対するレビュー・回答
│   └── handover/         チャット引継ぎメモ（git対象外）
├── isa/                  ISA各世代を明示的に保持（v1.0〜v3.0）。古い版も圧縮・隠蔽しない
│   ├── v1.0/〜v2.3/       各世代のアセンブラ・エミュレータ・テストプログラム
│   │   └── v1.0/fpga/    v1.0時代のFPGA試作RTL
│   └── v3.0/             ISA仕様検討中（現行開発）
├── src/
│   ├── toolchain/        現行ツールチェーン（scc22/scc23, force, サンプル等）
│   ├── os/                YUI OS本体（microkernel = Forthベースのマイクロカーネル）
│   ├── fpga/              FPGA RTL現行版（testvector/・generators/を含む）
│   └── dhrystone/         Dhrystoneベンチマーク（サードパーティ・git対象外）
├── demo/
│   ├── yuios/             YUI OSデモ
│   └── dhrystone/         Dhrystoneベンチマークのデモビルド
├── scripts/               ビルド・監査・生成スクリプト類
├── dist/                  YSD8800向け配布物（ROM/ディスクイメージ等のバイナリ）
└── build/                 x86ホストツール（git対象外。ソースからビルドする）
```

上記以外に、ビルド作業用の一時ディレクトリ（`yuios_build/`・`dhrystone_build/`・`kf_r2_build/`・`dist_tmp/`）、メモ用の`TMP/`・`TXT/`、旧アーカイブの`archives/`がありますが、いずれもgit対象外です。

## ライセンス

[MIT License](LICENSE)
