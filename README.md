# YSD8800

オリジナル16bit CPU YSD8800のページへようこそ。

公式ページ: https://yukarisemicon.netlify.app/works/ysd8800/

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
│   ├── reference/        版数管理台帳（design_inventory・各ledger）
│   └── reviews/          各設計書に対するレビュー・回答
├── isa/                  ISA各世代を明示的に保持（v1.0〜v3.0）。古い版も圧縮・隠蔽しない
│   ├── v1.0/〜v2.3/       各世代のアセンブラ・エミュレータ・テストプログラム
│   │   └── v1.0/fpga/    v1.0時代のFPGA試作RTL
│   └── v3.0/             ISA仕様検討中（現行開発）
├── src/
│   ├── toolchain/        現行ツールチェーン（scc22/scc23, force, サンプル等）
│   ├── os/                YUI OS本体（microkernel = Forthベースのマイクロカーネル）
│   └── fpga/              FPGA RTL現行版（testvector/・generators/を含む）
├── demo/                 YUI OS / Dhrystoneのデモ
├── scripts/               ビルド・監査・生成スクリプト類
└── dist/                 YSD8800向け配布物（ROM/ディスクイメージ等のバイナリ）
```

## 開発環境

- Linux Debian12

## ライセンス

[MIT License](LICENSE)
