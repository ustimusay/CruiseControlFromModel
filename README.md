# CruiseControlFromModel

Simulink によるクルーズコントロール制御ソフトウェアのモデルベース開発デモプロジェクトです。
要件定義、Simulink モデル、Data Dictionary、Simulink Test、Requirements Toolbox のトレーサビリティ、MCDC レポート生成までの一連の成果物を含みます。

## システム概要

`crs_controller.slx` は車両のクルーズコントロール制御ロジックを実装します。ドライバスイッチ、ブレーキ、車速、キー、ギア、前方車両との距離を入力として受け取り、クルーズコントロールの状態、動作モード、目標速度、スロットル指令を出力します。

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
| `throtDrv` | double | ドライバスロットル開度 (%) |
| `key` | uint8 | イグニッションキー状態 |
| `gear` | uint8 | ギア位置 |
| `frontDistance` | single | 前方車両との距離 (mm) |

### 出力信号

| 信号名 | 型 | 説明 |
|---|---|---|
| `throtCC` | double | クルーズコントロール制御スロットル指令 (%) |
| `targetSp` | double | 目標速度 (km/h) |
| `status` | boolean | クルーズコントロール動作ステータス |
| `mode` | `opMode` | 動作モード (`Disable`, `Enable`, `Activate`, `Resume`, `Increment`, `IncrHold`, `Decrement`, `DecrHold`) |

## アーキテクチャ

`crs_controller.slx` は主に以下の3つのトップレベルサブシステムで構成されます。

```text
crs_controller
├── DriverSwRequest        # ドライバスイッチ入力の正規化
├── CruiseControlMode      # ステータスと動作モードの管理
└── TargetSpeedThrottle    # 目標速度とスロットル指令の算出
```

### DriverSwRequest

`enbl`, `cncl`, `set`, `resume`, `inc`, `dec` を処理し、優先順位付きのスイッチ判定によって単一の要求信号 `reqDrv` へ正規化します。連続入力の抑止、短押し・中押し・長押しの判定、インクリメント/デクリメント要求の生成を担当します。

### CruiseControlMode

`reqDrv`, `brakeP`, `vehSp`, `key`, `gear`, `frontDistance` を入力として、`status` と `mode` を決定します。
通常の Enable / Activate / Resume / Disable 遷移に加えて、前方距離センサーによる自動 Enable 遷移を実装しています。

前方距離機能:

- `frontDistance` は mm 単位の `single` 入力です。
- 閾値は Data Dictionary の `Simulink.Parameter` `FrontDistanceThreshold_mm` で管理します。
- `FrontDistanceThreshold_mm = single(5000)`、単位は `mm` です。
- 動作モードが `opMode.Activate` で、かつ `frontDistance <= FrontDistanceThreshold_mm` の場合、モードを `opMode.Enable` へ自動遷移します。
- `Activate` 以外の状態、または 5 m 超過時には、`frontDistance` 単独では `Enable` 遷移を指令しません。

### TargetSpeedThrottle

`mode`, `vehSp`, `throtDrv` を入力として、`targetSp` と `throtCC` を算出します。`Activate`, `Resume`, `Increment`, `Decrement` 系のモードでは目標速度更新と PI 制御を行い、`Disable` / `Enable` では安全側の出力またはドライバ入力のパススルーを行います。

## 要件とトレーサビリティ

要件セットは `crs_controller_requirements.slreqx` に格納されています。

| 種別 | 件数 |
|---|---:|
| Container 要件 | 38 |
| Functional 要件 | 191 |
| 合計 | 229 |

主な要件グループ:

| サブシステム | 主な対象 |
|---|---|
| DriverSwRequest | スイッチ優先順位、連続入力抑止、inc/dec 判定 |
| CruiseControlMode | enable / disable / activate / resume 条件、前方距離による自動 Enable |
| TargetSpeedThrottle | 目標速度更新、スロットル制御、飽和、PI 制御 |

### 前方距離機能の追加要件

| 要件ID | Summary |
|---|---|
| `#236` | frontDistance single入力の受け渡し |
| `#237` | frontDistance 5m閾値判定 |
| `#238` | Activate中の前方距離による自動Enable遷移 |
| `#239` | 非Activate状態または5m超過時の自動Enable抑止 |

### リンク

| リンク種別 | 件数 | 説明 |
|---|---:|---|
| Implement | 284 | モデル要素から Functional 要件への実装リンク |
| Verify | 299 | Simulink Test のテストケースから Functional 要件への検証リンク |

TC48/TC49 は前方距離機能の要件 `#236`〜`#239` に Verify リンクされています。

## テスト

Simulink Test による MCDC テストスイートを管理しています。

| サブシステム | テストファイル | TC数 | ハーネス |
|---|---|---:|---|
| DriverSwRequest | `tests/DriverSwRequest_MCDC_Tests.mldatx` | 32 | `DriverSwRequest_MCDC_Harness` |
| CruiseControlMode | `tests/CruiseControlMode_MCDC_Tests.mldatx` | 48 | `CCMode_MCDC_Probe` |
| TargetSpeedThrottle | `tests/TST_MCDC_Tests.mldatx` | 16 | `TST_MCDC_Harness` |

`CruiseControlMode_MCDC_Tests.mldatx` は `TC01`〜`TC46`、`TC48`、`TC49` を含みます。現在のテストファイルに `TC47` はありません。

前方距離機能の追加テスト:

| テストケース | 検証内容 |
|---|---|
| `TC48_FrontDistanceAutoEnable` | `Activate` 中に `frontDistance <= 5000 mm` となった場合、`Enable` へ自動遷移すること |
| `TC49_FrontDistanceAboveThreshold` | `frontDistance > 5000 mm` の場合、前方距離入力だけでは `Enable` へ遷移しないこと |

テスト入力と期待値:

- `tests/test_inputs_ccm/TC48_FrontDistanceAutoEnable.mat`
- `tests/test_inputs_ccm/TC49_FrontDistanceAboveThreshold.mat`
- `tests/baselines_ccm/TC48_FrontDistanceAutoEnable_expected.mat`
- `tests/baselines_ccm/TC49_FrontDistanceAboveThreshold_expected.mat`

## レポート

MCDC トレーサビリティレポートは PDF として生成されます。

| 対象 | レポート |
|---|---|
| DriverSwRequest | `reports/report_dsr_mcdc/DriverSwRequest_MCDC_report.pdf` |
| CruiseControlMode | `reports/report_ccm_mcdc/CruiseControlMode_MCDC_report.pdf` |
| TargetSpeedThrottle | `reports/report_tst_mcdc/TargetSpeedThrottle_MCDC_report.pdf` |

レポートには以下が含まれます。

- テストケース情報と Pass / Fail 結果
- Verify リンク先の要件 ID、Summary、Description、Rationale
- 入力波形と期待出力波形
- Model Slicer による動的スライス画像

生成スクリプト:

```matlab
openProject('CruiseControlFromModel.prj');

run('reports/generate_DriverSwRequest_MCDC_report.m');
run('reports/generate_CruiseControlMode_MCDC_report.m');
run('reports/generate_TargetSpeedThrottle_MCDC_report.m');
```

`reports/generate_mcdc_report.m` は共通レポート生成関数です。`skipTestRun`, `reuseWaveforms`, `reuseSlicerImages`, `openReport` の設定により、既存テスト結果や既存画像を再利用したPDF再生成にも対応します。

## フォルダ構成

```text
CruiseControlFromModel/
├── crs_controller.slx
├── crs_plant.slx
├── crs_controller_requirements.slreqx
├── CruiseControlFromModel.prj
├── data/
│   ├── crs_controllerdic.sldd
│   ├── crs_plantdic.sldd
│   ├── crs_data.mat
│   ├── opMode.m
│   └── reqMode.m
├── tests/
│   ├── DriverSwRequest_MCDC_Tests.mldatx
│   ├── CruiseControlMode_MCDC_Tests.mldatx
│   ├── TST_MCDC_Tests.mldatx
│   ├── baselines/
│   ├── baselines_ccm/
│   ├── baselines_tst/
│   ├── test_inputs/
│   ├── test_inputs_ccm/
│   └── test_inputs_tst/
├── utils/
│   ├── add_DriverSwRequest_BlockRequirements.m
│   ├── add_TargetSpeedThrottle_BlockRequirements.m
│   ├── add_FrontDistanceAutoEnable_Requirements.m
│   ├── create_DriverSwRequest_VerifyLinks.m
│   ├── create_TST_VerifyLinks.m
│   ├── create_FrontDistance_VerifyLinks.m
│   └── update_FrontDistance_Requirements_Japanese.m
└── reports/
    ├── generate_mcdc_report.m
    ├── generate_DriverSwRequest_MCDC_report.m
    ├── generate_CruiseControlMode_MCDC_report.m
    ├── generate_TargetSpeedThrottle_MCDC_report.m
    ├── report_dsr_mcdc/
    ├── report_ccm_mcdc/
    └── report_tst_mcdc/
```

## 動作環境

- MATLAB R2025b で確認
- Simulink
- Simulink Test
- Requirements Toolbox
- Simulink Design Verifier / Model Slicer
- MATLAB Report Generator
