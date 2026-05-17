# CruiseControlFromModel

Simulink によるクルーズコントロール制御ソフトウェアのモデルベース開発デモプロジェクトです。
要件定義・モデル設計・実装リンク・テスト・トレーサビリティレポート生成までの一連のワークフローを収録しています。

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
| `throtDrv` | double | ドライバースロットル開度 (%) |
| `key` | uint8 | イグニッションキー状態 |
| `gear` | uint8 | ギア位置 |

### 出力信号

| 信号名 | 型 | 説明 |
|---|---|---|
| `throtCC` | double | CC制御スロットル指令値 (%) |
| `targetSp` | double | 目標速度 (km/h) |
| `status` | boolean | CC動作ステータス |
| `mode` | opMode | 動作モード (Disable / Enable / Activate / Resume / ...) |

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
| Disable | 保持 | 0 |
| Enable | Set時の車速を保存 | throtDrv をパススルー |
| Activate / Resume / Increment / Decrement | inc/dec 操作で更新 | PI フィードバック制御出力 |

---

## 要件

`crs_controller_requirements.slreqx` に **225件の要件**（Container 38件 + Functional 187件）を定義しています。

| サブシステム | Container | 主な Functional 要件の対象 |
|---|---|---|
| DriverSwRequest | #1（+ 内部 Container 群） | 各スイッチ論理、inc/dec、doNot Repeat の全ブロック |
| CruiseControlMode | #2（+ 内部 Container 群） | enable/disable/activate/resume 各条件判定ブロック |
| TargetSpeedThrottle | #3（+ 内部 Container 群） | toBoolean、targetSpeed、getNewTargetSpeed、PI制御、UsePI 等の全ブロック |

### モデルとのリンク

| リンク種別 | 件数 | 説明 |
|---|---|---|
| Implement | 266 | モデルブロック → Functional 要件（実装根拠） |
| Verify | 295 | テストケース → Functional 要件（検証根拠） |

---

## フォルダ構成

```
CruiseControlFromModel/
├── crs_controller.slx                  # 制御モデル
├── crs_plant.slx                       # プラントモデル
├── crs_controller_requirements.slreqx # 要件セット (225件)
├── CruiseControlFromModel.prj          # MATLAB Project ファイル
├── data/
│   ├── crs_controllerdic.sldd          # データディクショナリ
│   ├── crs_plantdic.sldd
│   ├── crs_data.mat
│   ├── opMode.m                        # 動作モード列挙定義
│   └── reqMode.m                       # 要求モード列挙定義
├── tests/
│   ├── DriverSwRequest_MCDC_Tests.mldatx    # DSR MCDC テストスイート (32 TC)
│   ├── CruiseControlMode_MCDC_Tests.mldatx  # CCM MCDC テストスイート (46 TC)
│   ├── TST_MCDC_Tests.mldatx                # TST MCDC テストスイート (16 TC)
│   ├── baselines/                      # DSR 期待出力 (.mat × 32)
│   ├── baselines_ccm/                  # CCM 期待出力 (.mat × 46)
│   ├── baselines_tst/                  # TST 期待出力 (.mat × 16)
│   ├── test_inputs/                    # DSR テスト入力信号 (.mat × 32)
│   ├── test_inputs_ccm/                # CCM テスト入力信号 (.mat × 46)
│   └── test_inputs_tst/                # TST テスト入力信号 (.mat × 16)
├── utils/
│   ├── setup_matlab_project.m                    # プロジェクトセットアップ
│   ├── add_DriverSwRequest_BlockRequirements.m   # DSR 要件・Implement リンク生成
│   ├── add_TargetSpeedThrottle_BlockRequirements.m # TST 要件・Implement リンク生成
│   ├── create_DriverSwRequest_MCDC_Tests.m       # DSR テストスイート生成
│   ├── create_DriverSwRequest_VerifyLinks.m      # DSR Verify リンク生成
│   └── create_TST_VerifyLinks.m                  # TST Verify リンク生成
└── reports/
    ├── generate_mcdc_report.m                        # 汎用 MCDC レポート生成関数
    ├── generate_DriverSwRequest_MCDC_report.m        # DSR レポート生成スクリプト
    ├── generate_CruiseControlMode_MCDC_report.m      # CCM レポート生成スクリプト
    ├── generate_TargetSpeedThrottle_MCDC_report.m    # TST レポート生成スクリプト
    ├── generate_ic_traceability_report.m             # IC トレーサビリティレポート生成
    ├── report_dsr_mcdc/
    │   └── DriverSwRequest_MCDC_report.pdf
    ├── report_ccm_mcdc/
    │   └── CruiseControlMode_MCDC_report.pdf
    └── report_tst_mcdc/
        └── TargetSpeedThrottle_MCDC_report.pdf
```

---

## テスト

全サブシステムで MCDC（Modified Condition/Decision Coverage）基準のテストスイートを完備し、**全テストケース Passed** を確認済みです。

### テストスイート一覧

| サブシステム | テストファイル | TC 数 | ハーネス | Verify リンク |
|---|---|---|---|---|
| DriverSwRequest | DriverSwRequest_MCDC_Tests.mldatx | 32 | DriverSwRequest_MCDC_Harness | 162 |
| CruiseControlMode | CruiseControlMode_MCDC_Tests.mldatx | 46 | CCMode_MCDC_Probe | 46 |
| TargetSpeedThrottle | TST_MCDC_Tests.mldatx | 16 | TST_MCDC_Harness | 83 |

### DriverSwRequest MCDC テストケース群

| テストケース群 | 対象 |
|---|---|
| TC01〜TC09 | 各スイッチ単独入力・優先度制御 |
| TC10〜TC14 | 連続重複入力の除去（doNot Repeat） |
| TC15〜TC23 | デクリメント操作（短押し・中押し・長押し・カウンタ） |
| TC24〜TC32 | インクリメント操作（短押し・中押し・長押し・カウンタ） |

### TargetSpeedThrottle MCDC テストケース群

| テストケース群 | 対象 |
|---|---|
| TC01〜TC04 | toBoolean NOR 論理（Disable / Enable / Activate / Resume） |
| TC05〜TC06 | targetSpeed LogicOp1 AND 論理（prev_isActivated / isEnabled 独立条件） |
| TC07〜TC10 | getNewTargetSpeed Switch チェーン（Increment / IncrementHold / Decrement / DecrementHold） |
| TC11〜TC12 | Saturation 境界（下限 40 km/h / 上限 100 km/h クランプ） |
| TC13〜TC15 | UsePI AND 論理（relop / RelOp 独立条件） |
| TC16 | Saturation2 下限境界（throtCC = 0% クランプ） |

### テストの実行

```matlab
% MATLAB Project を開く
openProject('CruiseControlFromModel.prj');

% 各テストスイートを実行（例: TargetSpeedThrottle）
tf = sltest.testmanager.load('tests/TST_MCDC_Tests.mldatx');
resultSet = tf.run();
```

### レポートの生成

```matlab
% Model Slicer ハイライト + 波形プロット付き PDF レポートを生成
run('reports/generate_DriverSwRequest_MCDC_report.m');
run('reports/generate_CruiseControlMode_MCDC_report.m');
run('reports/generate_TargetSpeedThrottle_MCDC_report.m');
```

各レポートには以下が含まれます:
- テストケース情報・テスト結果（Pass / Fail）
- 紐づく要件（Verify リンク先の ID・Summary・Description・Rationale）
- 入力波形 + 期待出力波形
- Model Slicer 動的スライス（TC ごとの実行パスをハイライト）

---

## 動作環境

- MATLAB R2023b 以降（R2025b で動作確認済み）
- Simulink
- Simulink Test
- Simulink Design Verifier（Model Slicer）
- MATLAB Report Generator
- Simulink Requirements
