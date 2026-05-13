# CruiseControlFromModel

Simulink によるクルーズコントロール制御ソフトウェアのモデルベース開発デモプロジェクトです。  
要件定義・モデル設計・テスト・トレーサビリティレポート生成までの一連のワークフローを収録しています。

---

## システム概要

車両のクルーズコントロール（CC）システムを制御するソフトウェアモデルです。  
ドライバーのスイッチ操作を入力として受け取り、走行条件に応じた動作モードを管理し、目標速度への追従スロットル指令値を出力します。

### 入力信号

| 信号名 | 型 | 説明 |
|---|---|---|
| `enbl` | boolean | クルーズコントロール有効化スイッチ |
| `cncl` | boolean | キャンセルスイッチ |
| `set` | boolean | 目標速度セットスイッチ |
| `resume` | boolean | 再開スイッチ |
| `inc` | boolean | 目標速度インクリメントスイッチ |
| `dec` | boolean | 目標速度デクリメントスイッチ |
| `brakeP` | boolean | ブレーキ操作検出 |
| `vehSp` | double | 車速 (km/h) |
| `throtDrv` | double | ドライバースロットル開度 |
| `key` | uint8 | イグニッションキー状態 |
| `gear` | uint8 | ギア位置 |

### 出力信号

| 信号名 | 型 | 説明 |
|---|---|---|
| `throtCC` | double | CC制御スロットル指令値 |
| `targetSp` | double | 目標速度 (km/h) |
| `status` | boolean | CC動作ステータス |
| `mode` | enum | 動作モード (Disabled / Enabled / Active / Resume) |

---

## アーキテクチャ

`crs_controller.slx` は以下の3つのトップレベルサブシステムで構成されます。

```
crs_controller
├── DriverSwRequest        — スイッチ入力の正規化
├── CruiseControlMode      — 動作状態・モード管理
└── TargetSpeedThrottle    — 目標速度・スロットル算出
```

### 1. DriverSwRequest

ドライバースイッチ入力（enbl / cncl / set / resume / inc / dec）を処理し、優先度付きスイッチング論理によって一意な要求信号 `reqDrv` へ正規化します。  
同時押しや連続重複押下（`doNot Repeat`）を除去することで、後段の状態機械が単一入力で制御判断できるようにします。

主な内部ロジック:
- **decrement / increment**: 短押し・中押し・長押しを判定し、スロットル操作量を生成。長押し時はカウンタによる継続操作を実現。
- **doNot Repeat**: 同一スイッチの連続入力を除去し、誤操作を防止。

### 2. CruiseControlMode

`reqDrv`、`brakeP`、`vehSp`、`key`、`gear` を入力として、CCの動作状態（`status`）と制御モード（`mode`）を決定します。  
走行条件に応じた安全な状態遷移管理を行い、不正な状態への遷移を防ぐことで機能安全要件を満たします。

動作モード遷移:

```
Disabled ──[enable条件]──► Enabled ──[activate条件]──► Active
    ▲                          │                          │
    └──[disable条件]───────────┘◄─────[resume条件]── Resume
```

主な遷移条件:
- **enable**: 車速が有効範囲内かつキーON・ドライブギア
- **activate**: Set スイッチ押下または Resume 操作
- **disable**: ブレーキ操作・キーOFF・ギア変更・車速範囲外

### 3. TargetSpeedThrottle

制御モード（`mode`）・車速（`vehSp`）・ドライバースロットル（`throtDrv`）を入力として、目標速度（`targetSp`）とスロットル指令値（`throtCC`）を算出します。

モード別動作:

| モード | targetSp | throtCC |
|---|---|---|
| Disabled | 保持 | 0 |
| Enabled | Set時の車速を保存 | throtDrv をパススルー |
| Active | inc/dec 操作で更新 | PI フィードバック制御出力 |
| Resume | 保存済み目標速度を復元 | PI フィードバック制御出力 |

---

## 要件

`crs_controller_requirements.slreqx` に37件の要件を定義しています。

| カテゴリ | 要件ID | 概要 |
|---|---|---|
| DriverSwRequest | #1〜#8 | スイッチ正規化・inc/dec・重複除去・カウンタ |
| CruiseControlMode | #9〜#26 | 有効化・無効化・アクティブ・再開の各条件判定 |
| TargetSpeedThrottle | #27〜#37 | モード別算出・PI制御・目標速度管理 |

---

## フォルダ構成

```
CruiseControlFromModel/
├── crs_controller.slx               # 制御モデル
├── crs_plant.slx                    # プラントモデル
├── crs_controller_requirements.slreqx  # 要件セット
├── CruiseControlFromModel.prj       # MATLAB Project ファイル
├── data/
│   ├── crs_controllerdic.sldd       # データディクショナリ
│   ├── crs_plantdic.sldd
│   ├── crs_data.mat
│   ├── opMode.m                     # 動作モード列挙定義
│   └── reqMode.m                    # 要求モード列挙定義
├── tests/
│   ├── DriverSwRequest_MCDC_Tests.mldatx  # MCDCテストスイート (32TC)
│   ├── baselines/                   # 期待出力 (.mat × 32)
│   └── test_inputs/                 # テスト入力信号 (.mat × 32)
├── utils/
│   ├── create_DriverSwRequest_MCDC_Tests.m   # テストスイート生成スクリプト
│   ├── create_DriverSwRequest_VerifyLinks.m  # 要件 Verify リンク生成スクリプト
│   └── setup_matlab_project.m               # プロジェクトセットアップスクリプト
└── reports/
    ├── generate_DriverSwRequest_MCDC_report.m  # MCDCトレーサビリティレポート生成
    ├── generate_ic_traceability_report.m       # IC トレーサビリティレポート生成
    └── report_dsr_mcdc/
        └── DriverSwRequest_MCDC_report.pdf     # 生成済みレポート
```

---

## テスト

### DriverSwRequest MCDC テストスイート

`DriverSwRequest` サブシステムに対して、MCDC（Modified Condition/Decision Coverage）基準で設計した32テストケースを収録しています。

| テストケース群 | 対象 |
|---|---|
| TC01〜TC09 | 各スイッチ単独入力・優先度制御 |
| TC10〜TC14 | 連続重複入力の除去（doNot Repeat） |
| TC15〜TC23 | デクリメント操作（短押し・中押し・長押し・カウンタ） |
| TC24〜TC32 | インクリメント操作（短押し・中押し・長押し・カウンタ） |

全32TC が **Passed** であることを確認済みです。

### テストの実行

```matlab
% MATLAB Project を開く
openProject('CruiseControlFromModel.prj');

% テストスイートを実行
tf = sltest.testmanager.load('tests/DriverSwRequest_MCDC_Tests.mldatx');
resultSet = tf.run();
```

### レポートの生成

```matlab
% Model Slicer ハイライト + 波形プロット付き PDF レポートを生成
run('reports/generate_DriverSwRequest_MCDC_report.m');
```

---

## 動作環境

- MATLAB R2023b 以降（R2025b で動作確認済み）
- Simulink
- Simulink Test
- Simulink Design Verifier（Model Slicer）
- MATLAB Report Generator
- Simulink Requirements
