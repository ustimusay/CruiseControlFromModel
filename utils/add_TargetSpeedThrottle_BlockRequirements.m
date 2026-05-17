%% add_TargetSpeedThrottle_BlockRequirements.m
% TargetSpeedThrottle サブシステムの階層構造に沿ったコンテナ要件を作成し、
% 非仮想ブロックに個別の Functional 要件を作成して Implement リンクを設定する。

rootDir = currentProject().RootFolder;
slreq.clear();

if ~bdIsLoaded('crs_controller')
    open_system(fullfile(rootDir, 'crs_controller.slx'));
    drawnow; pause(1);
end

rs = slreq.load(fullfile(rootDir, 'crs_controller_requirements.slreqx'));

% 既存の TargetSpeedThrottle 要件 (#3) を取得して Container に変換
rTST = find(rs, 'Type', 'Requirement', 'Id', '#3');
if strcmp(rTST.Type, 'Functional')
    rTST.Type = 'Container';
end

% ブロックパス定義
tstPath    = 'crs_controller/TargetSpeedThrottle';
actPath    = [tstPath  '/activated'];
gntsPath   = [actPath  '/getNewTargetSpeed'];
gtvPath    = [actPath  '/getThrottleValue'];
piPath     = [gtvPath  '/PI controller'];
usepiPath  = [gtvPath  '/UsePI'];
disPath    = [tstPath  '/disabled'];
enPath     = [tstPath  '/enabled'];
tsPath     = [tstPath  '/targetSpeed'];
storePath  = [tsPath   '/storeSpeed'];
toBoolPath = [tstPath  '/toBoolean'];

%% ====================================================================
%%  サブシステム コンテナ要件の作成
%% ====================================================================

%% --- toBoolean ---
rToBoolean = add(rTST, 'Type', 'Container');
rToBoolean.Summary     = 'toBoolean: 動作モードのブール変換';
rToBoolean.Description = ['入力 mode（opMode 列挙値）を Disable / Enable / Resume / Activate の' ...
    '各ブール信号（isDisabled / isEnabled / isResumed / isActivated）に変換する。'];
rToBoolean.Rationale   = ['後続サブシステム（disabled / enabled / activated）のイネーブル制御および' ...
    ' targetSpeed の格納条件判断に使用するため、モード列挙値をブール値に分解する必要がある。'];

%% --- disabled ---
rDisabled = add(rTST, 'Type', 'Container');
rDisabled.Summary     = 'disabled: クルーズ無効時の出力';
rDisabled.Description = ['クルーズ無効（Disable）モード時に目標速度として最小値（tsp_min = 40 km/h）を出力し、' ...
    'スロットル指令値はドライバー入力（throtDrv）をパススルーする。'];
rDisabled.Rationale   = ['無効状態では目標速度を保持する意味がないため、' ...
    '最小値を出力してシステムの初期状態を明示する。'];

%% --- enabled ---
rEnabled = add(rTST, 'Type', 'Container');
rEnabled.Summary     = 'enabled: クルーズ有効待機時の出力';
rEnabled.Description = ['有効（Enable）モード時に車速（vehSp）を目標速度として、' ...
    'ドライバースロットル（throtDrv）をスロットル指令値としてパススルーする。'];
rEnabled.Rationale   = ['クルーズ有効待機中はアクティベートを待つため、' ...
    '現在の車速を目標速度とし、クルーズ制御を介入させない。'];

%% --- targetSpeed ---
rTargetSpeed = add(rTST, 'Type', 'Container');
rTargetSpeed.Summary     = 'targetSpeed: 目標速度の状態管理';
rTargetSpeed.Description = ['再開（Resume）時は格納済み目標速度を、' ...
    'それ以外は前サンプルの Merge 出力を目標速度として供給する。' ...
    'アクティブ→有効への遷移時に storeSpeed が目標速度を格納する。'];
rTargetSpeed.Rationale   = ['クルーズを一時解除した後に再開する際、解除前の目標速度を復元するために' ...
    '状態保持機構が必要である。'];

%% --- storeSpeed (targetSpeed 配下) ---
rStoreSpeed = add(rTargetSpeed, 'Type', 'Container');
rStoreSpeed.Summary     = 'storeSpeed: 目標速度のサンプルホールド';
rStoreSpeed.Description = ['LogicOp1 がアサートされたサンプルに限り、' ...
    '前サンプルの目標速度（targetSp_prev）をイネーブルサブシステムのホールド動作で保持して出力する。'];
rStoreSpeed.Rationale   = ['Resume 時に参照する格納済み目標速度を保持するため、' ...
    'アクティブ→有効遷移のタイミングでサンプルホールドが必要である。'];

%% --- activated ---
rActivated = add(rTST, 'Type', 'Container');
rActivated.Summary     = 'activated: アクティブ時の目標速度・スロットル算出';
rActivated.Description = ['アクティブ（Activate）モード時に、操作モード（mode）に応じた目標速度を算出するとともに、' ...
    'PI 制御またはドライバースロットルを用いてスロットル指令値を出力する。'];
rActivated.Rationale   = ['クルーズコントロールがアクティブな間、ドライバーのスイッチ操作に応じた速度変更と、' ...
    '車速を目標速度に追従させる制御則が必要である。'];

%% --- getNewTargetSpeed (activated 配下) ---
rGNTS = add(rActivated, 'Type', 'Container');
rGNTS.Summary     = 'getNewTargetSpeed: 操作モードに応じた目標速度の更新';
rGNTS.Description = ['操作モード（Activate / Increment / IncrementHold / Decrement / DecrementHold）に応じて' ...
    '目標速度を保持・増減させ、許容範囲 [tsp_min = 40, tsp_max = 100] km/h にクランプして出力する。'];
rGNTS.Rationale   = ['ドライバーのスイッチ操作をリアルタイムで目標速度に反映し、' ...
    '安全な速度範囲内に収めるために必要である。'];

%% --- getThrottleValue (activated 配下) ---
rGTV = add(rActivated, 'Type', 'Container');
rGTV.Summary     = 'getThrottleValue: スロットル指令値の選択と制限';
rGTV.Description = ['PI 制御出力とドライバースロットルを UsePI の判定結果で切り替え、' ...
    '許容範囲 [throt_min = 0, throt_max = 100] % にクランプしてスロットル指令値を出力する。'];
rGTV.Rationale   = ['PI 制御が車速を目標速度へ追従させる際に必要なスロットルを計算し、' ...
    'ドライバー操作との円滑な切り替えを実現するために必要である。'];

%% --- PI controller (getThrottleValue 配下) ---
rPI = add(rGTV, 'Type', 'Container');
rPI.Summary     = 'PI controller: 比例積分制御によるスロットル計算';
rPI.Description = ['目標速度と車速の偏差（targetSpIn - vehSp）を比例積分制御則で処理し、' ...
    'スロットル指令値（throt）を算出する。比例ゲイン Kp = 20、サンプル時間 Ts = 0.01 s。'];
rPI.Rationale   = ['車速を目標速度に定常偏差なく追従させるため、' ...
    '比例項と積分項を組み合わせた閉ループ制御が必要である。'];

%% --- UsePI (getThrottleValue 配下) ---
rUsePI = add(rGTV, 'Type', 'Container');
rUsePI.Summary     = 'UsePI: PI 制御使用条件の判定';
rUsePI.Description = ['PI スロットル出力がドライバースロットル以上（throtPI >= throtDrv）、' ...
    'かつ目標速度が車速を超えている（targetSpIn > vehSp）とき、PI 制御を使用すると判定する。'];
rUsePI.Rationale   = ['車速が目標速度を超えている場合や PI 出力がドライバー操作より小さい場合は' ...
    'ドライバー操作を優先することで、制御の安全性と乗り心地を確保する。'];

%% ====================================================================
%%  個別ブロック Functional 要件の作成
%% ====================================================================

%% ── toBoolean 配下 ────────────────────────────────────────────────────

rTB_EC_Dis = add(rToBoolean);
rTB_EC_Dis.Summary     = 'opMode.Disable 定数の定義';
rTB_EC_Dis.Description = 'opMode.Disable を列挙定数として定義し、relop1 の比較基準値として供給する。';
rTB_EC_Dis.Rationale   = '列挙型定数を明示的に定義することで、比較演算に型安全性と可読性を与える。';

rTB_EC_Res = add(rToBoolean);
rTB_EC_Res.Summary     = 'opMode.Resume 定数の定義';
rTB_EC_Res.Description = 'opMode.Resume を列挙定数として定義し、relop3 の比較基準値として供給する。';
rTB_EC_Res.Rationale   = '列挙型定数を明示的に定義することで、比較演算に型安全性と可読性を与える。';

rTB_EC_En = add(rToBoolean);
rTB_EC_En.Summary     = 'opMode.Enable 定数の定義';
rTB_EC_En.Description = 'opMode.Enable を列挙定数として定義し、relop2 の比較基準値として供給する。';
rTB_EC_En.Rationale   = '列挙型定数を明示的に定義することで、比較演算に型安全性と可読性を与える。';

rTB_relop1 = add(rToBoolean);
rTB_relop1.Summary     = 'Disable モードの判定';
rTB_relop1.Description = 'mode == opMode.Disable のとき true を出力し、isDisabled 信号として後続の disabled サブシステムイネーブルに供給する。';
rTB_relop1.Rationale   = 'クルーズ無効状態を他のモードと区別するため、個別のブール信号として抽出する。';

rTB_relop2 = add(rToBoolean);
rTB_relop2.Summary     = 'Enable モードの判定';
rTB_relop2.Description = 'mode == opMode.Enable のとき true を出力し、isEnabled 信号として enabled サブシステムイネーブルと targetSpeed の格納条件に供給する。';
rTB_relop2.Rationale   = 'クルーズ有効待機状態を他のモードと区別するため、個別のブール信号として抽出する。';

rTB_relop3 = add(rToBoolean);
rTB_relop3.Summary     = 'Resume モードの判定';
rTB_relop3.Description = 'mode == opMode.Resume のとき true を出力し、isResumed 信号として targetSpeed の再開選択に供給する。';
rTB_relop3.Rationale   = '一時解除後の再開状態を他のモードと区別するため、個別のブール信号として抽出する。';

rTB_LogicOp = add(rToBoolean);
rTB_LogicOp.Summary     = 'Activate モードの判定（NOR）';
rTB_LogicOp.Description = ['isDisabled / isEnabled / isResumed の NOR 演算により、' ...
    'これらすべてが false のとき（すなわち mode == Activate のとき）true を出力して isActivated 信号とする。'];
rTB_LogicOp.Rationale   = ['クルーズアクティブ状態は他の 3 モードのいずれでもない状態として定義されるため、' ...
    'NOR によるデコードが適切である。'];

%% ── disabled 配下 ────────────────────────────────────────────────────

rDis_Const = add(rDisabled);
rDis_Const.Summary     = '無効時の目標速度最小値定数（tsp_min = 40 km/h）';
rDis_Const.Description = 'クルーズ無効（Disable）モード時の目標速度として tsp_min（40 km/h）を定数出力する。';
rDis_Const.Rationale   = '無効状態の初期目標速度を最小許容値に設定することで、再有効化時の安全なデフォルト動作を保証する。';

%% ── targetSpeed 配下 ────────────────────────────────────────────────

rTS_UD1 = add(rTargetSpeed);
rTS_UD1.Summary     = '前サンプルの Activate 信号保持（UnitDelay1）';
rTS_UD1.Description = 'isActivated を 1 サンプル遅延させ、LogicOp1 の入力として供給する。';
rTS_UD1.Rationale   = ['アクティブ→有効への遷移（isActivated の立ち下がり）を検出するため、' ...
    '前サンプルの isActivated が必要である。'];

rTS_Logic = add(rTargetSpeed);
rTS_Logic.Summary     = 'スピード格納条件の論理積（LogicOp1）';
rTS_Logic.Description = ['isEnabled（現サンプルで有効モード）と UnitDelay1 出力（前サンプルの isActivated）の AND を算出し、' ...
    'storeSpeed サブシステムのイネーブル信号として使用する。'];
rTS_Logic.Rationale   = ['アクティブから有効へ遷移した直後のサンプルでのみ目標速度を格納することで、' ...
    '最後のアクティブ目標速度を保持できる。'];

rTS_Sw5 = add(rTargetSpeed);
rTS_Sw5.Summary     = '再開時の目標速度選択（Switch5）';
rTS_Sw5.Description = ['isResumed が true のとき storeSpeed の格納済み目標速度を、' ...
    'false のとき前サンプルの Merge 出力（targetSp_in）を選択して出力する。'];
rTS_Sw5.Rationale   = 'Resume 時にクルーズ解除前の目標速度を復元するため、格納値と現在値を切り替える選択が必要である。';

%% ── getNewTargetSpeed 配下 ──────────────────────────────────────────

rGNTS_EC_Act = add(rGNTS);
rGNTS_EC_Act.Summary     = 'opMode.Activate 定数の定義（getNewTargetSpeed）';
rGNTS_EC_Act.Description = 'opMode.Activate を列挙定数として定義し、RelationalOperator2 の比較基準値として供給する。';
rGNTS_EC_Act.Rationale   = '型安全な列挙型比較を行うため、モード定数を明示的に定義する。';

rGNTS_EC_IncH = add(rGNTS);
rGNTS_EC_IncH.Summary     = 'opMode.IncrementHold 定数の定義';
rGNTS_EC_IncH.Description = 'opMode.IncrementHold を列挙定数として定義し、RelationalOperator3 の比較基準値として供給する。';
rGNTS_EC_IncH.Rationale   = '型安全な列挙型比較を行うため、モード定数を明示的に定義する。';

rGNTS_EC_Inc = add(rGNTS);
rGNTS_EC_Inc.Summary     = 'opMode.Increment 定数の定義';
rGNTS_EC_Inc.Description = 'opMode.Increment を列挙定数として定義し、RelationalOperator1 の比較基準値として供給する。';
rGNTS_EC_Inc.Rationale   = '型安全な列挙型比較を行うため、モード定数を明示的に定義する。';

rGNTS_EC_Dec = add(rGNTS);
rGNTS_EC_Dec.Summary     = 'opMode.Decrement 定数の定義';
rGNTS_EC_Dec.Description = 'opMode.Decrement を列挙定数として定義し、RelationalOperator4 の比較基準値として供給する。';
rGNTS_EC_Dec.Rationale   = '型安全な列挙型比較を行うため、モード定数を明示的に定義する。';

rGNTS_C_inc_s = add(rGNTS);
rGNTS_C_inc_s.Summary     = '短押しインクリメント量定数（target_inc_short = 1 km/h）';
rGNTS_C_inc_s.Description = 'Increment 操作時に目標速度に加算する増分量 target_inc_short（1 km/h）を定数として定義し、Add1 に供給する。';
rGNTS_C_inc_s.Rationale   = '短押し操作に対する目標速度の増分量を定数として明示し、パラメータ変更を容易にする。';

rGNTS_C_inc_h = add(rGNTS);
rGNTS_C_inc_h.Summary     = '長押しインクリメント量定数（target_inc_hold = 0.05 km/h）';
rGNTS_C_inc_h.Description = 'IncrementHold 操作時に目標速度に加算する増分量 target_inc_hold（0.05 km/h）を定数として定義し、Add2 に供給する。';
rGNTS_C_inc_h.Rationale   = '長押し操作に対する目標速度の微小増分量を定数として明示し、パラメータ変更を容易にする。';

rGNTS_C_dec_s = add(rGNTS);
rGNTS_C_dec_s.Summary     = '短押しデクリメント量定数（target_dec_short = 1 km/h）';
rGNTS_C_dec_s.Description = 'Decrement 操作時に目標速度から減算する減分量 target_dec_short（1 km/h）を定数として定義し、Add3 に供給する。';
rGNTS_C_dec_s.Rationale   = '短押し操作に対する目標速度の減分量を定数として明示し、パラメータ変更を容易にする。';

rGNTS_C_dec_h = add(rGNTS);
rGNTS_C_dec_h.Summary     = '長押しデクリメント量定数（target_dec_hold = 0.05 km/h）';
rGNTS_C_dec_h.Description = 'DecrementHold 操作時に目標速度から減算する減分量 target_dec_hold（0.05 km/h）を定数として定義し、Add4 に供給する。';
rGNTS_C_dec_h.Rationale   = '長押し操作に対する目標速度の微小減分量を定数として明示し、パラメータ変更を容易にする。';

rGNTS_Add1 = add(rGNTS);
rGNTS_Add1.Summary     = 'Increment 短押し後の目標速度計算（Add1）';
rGNTS_Add1.Description = 'targetSpIn に target_inc_short（1 km/h）を加算し、Increment 操作時の目標速度候補値を算出する。';
rGNTS_Add1.Rationale   = 'Increment 操作の結果を Switch1 で選択できるよう事前に計算する。';

rGNTS_Add2 = add(rGNTS);
rGNTS_Add2.Summary     = 'IncrementHold 長押し後の目標速度計算（Add2）';
rGNTS_Add2.Description = 'targetSpIn に target_inc_hold（0.05 km/h）を加算し、IncrementHold 操作時の目標速度候補値を算出する。';
rGNTS_Add2.Rationale   = 'IncrementHold 操作の結果を Switch2 で選択できるよう事前に計算する。';

rGNTS_Add3 = add(rGNTS);
rGNTS_Add3.Summary     = 'Decrement 短押し後の目標速度計算（Add3）';
rGNTS_Add3.Description = 'targetSpIn から target_dec_short（1 km/h）を減算し、Decrement 操作時の目標速度候補値を算出する。';
rGNTS_Add3.Rationale   = 'Decrement 操作の結果を Switch3 で選択できるよう事前に計算する。';

rGNTS_Add4 = add(rGNTS);
rGNTS_Add4.Summary     = 'DecrementHold 長押し後の目標速度計算（Add4）';
rGNTS_Add4.Description = 'targetSpIn から target_dec_hold（0.05 km/h）を減算し、DecrementHold 操作時の目標速度候補値を算出する。';
rGNTS_Add4.Rationale   = 'DecrementHold 操作の結果を Switch3 のデフォルト入力として使用できるよう事前に計算する。';

rGNTS_RelOp1 = add(rGNTS);
rGNTS_RelOp1.Summary     = 'Increment モードの判定（RelationalOperator1）';
rGNTS_RelOp1.Description = 'mode == opMode.Increment のとき true を出力し、Switch1 の選択制御信号として使用する。';
rGNTS_RelOp1.Rationale   = '4 段階の速度変化モードを個別の Switch に振り分けるため、各モードを個別に判定する。';

rGNTS_RelOp2 = add(rGNTS);
rGNTS_RelOp2.Summary     = 'Activate モードの判定（RelationalOperator2）';
rGNTS_RelOp2.Description = 'mode == opMode.Activate のとき true を出力し、Switch の選択制御信号として使用する。Activate 時は目標速度を変更せず保持する。';
rGNTS_RelOp2.Rationale   = 'Activate モードでは速度変化を行わない（保持）ことを実装するため、個別に判定する。';

rGNTS_RelOp3 = add(rGNTS);
rGNTS_RelOp3.Summary     = 'IncrementHold モードの判定（RelationalOperator3）';
rGNTS_RelOp3.Description = 'mode == opMode.IncrementHold のとき true を出力し、Switch2 の選択制御信号として使用する。';
rGNTS_RelOp3.Rationale   = '4 段階の速度変化モードを個別の Switch に振り分けるため、各モードを個別に判定する。';

rGNTS_RelOp4 = add(rGNTS);
rGNTS_RelOp4.Summary     = 'Decrement モードの判定（RelationalOperator4）';
rGNTS_RelOp4.Description = 'mode == opMode.Decrement のとき true を出力し、Switch3 の選択制御信号として使用する。';
rGNTS_RelOp4.Rationale   = '4 段階の速度変化モードを個別の Switch に振り分けるため、各モードを個別に判定する。';

rGNTS_Sw = add(rGNTS);
rGNTS_Sw.Summary     = 'Activate 時の目標速度保持選択（Switch）';
rGNTS_Sw.Description = ['mode == Activate のとき targetSpIn をそのまま通過させる（目標速度保持）。' ...
    'Activate でないとき Switch1 の出力を選択する。'];
rGNTS_Sw.Rationale   = 'アクティベート直後に目標速度が変化しないよう、Activate モードでは現在値を保持するための優先選択が必要である。';

rGNTS_Sw1 = add(rGNTS);
rGNTS_Sw1.Summary     = 'Increment 時の短押し速度選択（Switch1）';
rGNTS_Sw1.Description = ['mode == Increment のとき Add1 の出力（targetSpIn + 1 km/h）を選択する。' ...
    'Increment でないとき Switch2 の出力を選択する。'];
rGNTS_Sw1.Rationale   = '優先度チェーンにより Increment モードを Activate より低優先で処理するための選択ブロックが必要である。';

rGNTS_Sw2 = add(rGNTS);
rGNTS_Sw2.Summary     = 'IncrementHold 時の長押し速度選択（Switch2）';
rGNTS_Sw2.Description = ['mode == IncrementHold のとき Add2 の出力（targetSpIn + 0.05 km/h）を選択する。' ...
    'IncrementHold でないとき Switch3 の出力を選択する。'];
rGNTS_Sw2.Rationale   = '優先度チェーンにより IncrementHold モードを Increment より低優先で処理するための選択ブロックが必要である。';

rGNTS_Sw3 = add(rGNTS);
rGNTS_Sw3.Summary     = 'Decrement / DecrementHold 時の速度選択（Switch3）';
rGNTS_Sw3.Description = ['mode == Decrement のとき Add3 の出力（targetSpIn - 1 km/h）を選択する。' ...
    'Decrement でないとき（DecrementHold）Add4 の出力（targetSpIn - 0.05 km/h）を選択する。'];
rGNTS_Sw3.Rationale   = '優先度チェーンの末端として Decrement と DecrementHold を 1 つの Switch で処理する。DecrementHold はデフォルト（else）入力として扱われる。';

rGNTS_Sat = add(rGNTS);
rGNTS_Sat.Summary     = '目標速度の速度範囲クランプ（Saturation）';
rGNTS_Sat.Description = 'Switch チェーンの出力を [tsp_min = 40 km/h, tsp_max = 100 km/h] にクランプし、目標速度が許容範囲を逸脱しないようにする。';
rGNTS_Sat.Rationale   = '操作によって目標速度が安全範囲を超えないよう、出力段でリミッタを設けることが必要である。';

%% ── PI controller 配下 ──────────────────────────────────────────────

rPI_Add = add(rPI);
rPI_Add.Summary     = '速度偏差の計算（Add）';
rPI_Add.Description = '目標速度（targetSpIn）から車速（vehSp）を減算して速度偏差（e = targetSpIn - vehSp）を算出し、比例項・積分項の共通入力として供給する。';
rPI_Add.Rationale   = 'PI 制御則の起点となる偏差信号を生成するために必要である。';

rPI_DTI = add(rPI);
rPI_DTI.Summary     = '積分項の離散計算（DTI）';
rPI_DTI.Description = ['速度偏差を離散積分（前進オイラー法）して積分項を算出する。' ...
    '更新式: y[k] = y[k-1] + e[k-1] * Ts（Ts = 0.01 s）。'];
rPI_DTI.Rationale   = '定常偏差を除去するため、積分項が必要である。PI controller がイネーブルのときのみ積分が更新される。';

rPI_Kp = add(rPI);
rPI_Kp.Summary     = '比例項の計算（Kp ゲイン）';
rPI_Kp.Description = '速度偏差に比例ゲイン Kp（= 20）を乗算して比例項（P 項）を算出する。';
rPI_Kp.Rationale   = '速度偏差に即時応答するための比例制御を実現するために必要である。';

rPI_Sum = add(rPI);
rPI_Sum.Summary     = 'PI 制御出力の合算（Sum）';
rPI_Sum.Description = '比例項（Kp × e）と積分項（DTI 出力）を加算して PI 制御によるスロットル指令値（throt）を算出する。';
rPI_Sum.Rationale   = '比例項と積分項を組み合わせることで定常偏差のない制御出力を生成するために必要である。';

%% ── UsePI 配下 ──────────────────────────────────────────────────────

rUPI_relop_sp = add(rUsePI);
rUPI_relop_sp.Summary     = '目標速度超過判定（relop: targetSpIn > vehSp）';
rUPI_relop_sp.Description = '目標速度（targetSpIn）が車速（vehSp）を上回るとき true を出力する。車速がまだ目標速度に達していない状態を判定する。';
rUPI_relop_sp.Rationale   = '車速が目標速度を超過している場合は PI スロットルが不要であるため、PI 使用条件の一部として判定する。';

rUPI_relop_th = add(rUsePI);
rUPI_relop_th.Summary     = 'PI スロットル優位性判定（RelationalOperator: throtPI >= throtDrv）';
rUPI_relop_th.Description = 'PI 制御スロットル出力（throtPI）がドライバースロットル（throtDrv）以上のとき true を出力する。';
rUPI_relop_th.Rationale   = 'ドライバーが PI 出力より大きいスロットルを踏んでいる場合は PI を無効化することで、ドライバー意図を優先する。';

rUPI_Logic = add(rUsePI);
rUPI_Logic.Summary     = 'PI 使用条件の論理積（LogicalOperator）';
rUPI_Logic.Description = ['throtPI >= throtDrv かつ targetSpIn > vehSp の両条件が成立するとき true を出力し、' ...
    'PI 制御を使用すると判定する（yesno 信号）。いずれかが false のときはドライバースロットルを優先する。'];
rUPI_Logic.Rationale   = '2 つの独立した安全条件を AND 合成することで PI 使用の必要十分条件を判定するために必要である。';

%% ── getThrottleValue 配下（UsePI / PI 以外） ───────────────────────

rGTV_Delay1 = add(rGTV);
rGTV_Delay1.Summary     = '前サンプルの PI 使用フラグ保持（Delay1）';
rGTV_Delay1.Description = ['UsePI の判定結果（yesno）を 1 サンプル遅延させ、' ...
    'PI controller サブシステムのイネーブル信号として使用する。'];
rGTV_Delay1.Rationale   = ['PI controller がイネーブルになる条件を 1 サンプル遅延させることで、' ...
    '現サンプルで PI 使用と判定されたとき次サンプルから積分を開始する設計とする。'];

rGTV_Sw = add(rGTV);
rGTV_Sw.Summary     = 'PI / ドライバースロットル選択（Switch）';
rGTV_Sw.Description = ['UsePI の判定結果（yesno）が true のとき PI controller 出力（throt）を、' ...
    'false のときドライバースロットル（throtDrv）を選択する。'];
rGTV_Sw.Rationale   = 'PI 制御とドライバー操作を UsePI 条件に基づいて切り替えることで、安全なスロットル出力を選択する。';

rGTV_Sat = add(rGTV);
rGTV_Sat.Summary     = 'スロットル指令値の範囲クランプ（Saturation2）';
rGTV_Sat.Description = 'Switch の出力を [throt_min = 0 %, throt_max = 100 %] にクランプし、物理的な許容範囲を保証する。';
rGTV_Sat.Rationale   = 'PI 制御の積分ワインドアップ等によりスロットル指令値が許容範囲を超えることを防止するために必要である。';

%% ── TargetSpeedThrottle トップレベル ───────────────────────────────

rMerge = add(rTST);
rMerge.Summary     = '3 モードからの目標速度マージ（Merge）';
rMerge.Description = ['disabled / enabled / activated の各イネーブルサブシステムから出力される目標速度（targetSp）を Merge ブロックで統合し、' ...
    '有効状態のサブシステムの出力を最終 targetSp として選択する。'];
rMerge.Rationale   = 'イネーブルサブシステムが排他的に動作するため、Merge ブロックによる統合で各モード出力をシングルワイヤに集約する必要がある。';

rMerge1 = add(rTST);
rMerge1.Summary     = '3 モードからのスロットル指令値マージ（Merge1）';
rMerge1.Description = ['disabled / enabled / activated の各イネーブルサブシステムから出力されるスロットル指令値（throtCC）を Merge ブロックで統合し、' ...
    '有効状態のサブシステムの出力を最終 throtCC として選択する。'];
rMerge1.Rationale   = 'イネーブルサブシステムが排他的に動作するため、Merge ブロックによる統合でスロットル出力をシングルワイヤに集約する必要がある。';

rUD = add(rTST);
rUD.Summary     = '前サンプル目標速度の保持（UnitDelay）';
rUD.Description = 'Merge で統合された目標速度を 1 サンプル遅延させ、targetSpeed サブシステムの targetSp_in として供給する。';
rUD.Rationale   = ['targetSpeed サブシステムが目標速度の前サンプル値を基準として Switch5 の選択を行うため、' ...
    '1 サンプル遅延による前値保持が必要である。'];

fprintf('Requirements created: done.\n');

%% ====================================================================
%%  Implement リンクの作成
%% ====================================================================

totalLinks = 0;

%% ── サブシステムブロック → コンテナ要件 ──────────────────────────

linkPairs_sub = {
    [tstPath '/toBoolean'],    rToBoolean;
    [tstPath '/disabled'],     rDisabled;
    [tstPath '/enabled'],      rEnabled;
    [tstPath '/targetSpeed'],  rTargetSpeed;
    [tsPath  '/storeSpeed'],   rStoreSpeed;
    [tstPath '/activated'],    rActivated;
    [actPath '/getNewTargetSpeed'], rGNTS;
    [actPath '/getThrottleValue'],  rGTV;
    [gtvPath '/PI controller'],     rPI;
    [gtvPath '/UsePI'],             rUsePI;
};
for i = 1:size(linkPairs_sub, 1)
    try
        h = get_param(linkPairs_sub{i,1}, 'Handle');
        slreq.createLink(h, linkPairs_sub{i,2});
        totalLinks = totalLinks + 1;
    catch e
        warning('Link failed for %s: %s', linkPairs_sub{i,1}, e.message);
    end
end

%% ── toBoolean ────────────────────────────────────────────────────────

% EnumConst ブロック（SubSystem）→ 値で振り分け
for blk = find_system(toBoolPath, 'SearchDepth', 1, 'BlockType', 'SubSystem')'
    name = get_param(blk{1}, 'Name');
    if strcmp(name, 'toBoolean'), continue; end  % 親自身はスキップ
    try
        vals = get_param(blk{1}, 'MaskValues');
        enumVal = vals{2};  % 2番目がValue
        if contains(enumVal, 'Disable')
            tgt = rTB_EC_Dis;
        elseif contains(enumVal, 'Resume')
            tgt = rTB_EC_Res;
        elseif contains(enumVal, 'Enable')
            tgt = rTB_EC_En;
        else
            continue;
        end
        slreq.createLink(get_param(blk{1}, 'Handle'), tgt);
        totalLinks = totalLinks + 1;
    catch e
        warning('toBoolean EnumConst link failed: %s', e.message);
    end
end

% RelationalOperator → 名前で振り分け
for blk = find_system(toBoolPath, 'SearchDepth', 1, 'BlockType', 'RelationalOperator')'
    name = get_param(blk{1}, 'Name');
    if strcmp(name, 'relop1')
        tgt = rTB_relop1;
    elseif strcmp(name, 'relop2')
        tgt = rTB_relop2;
    elseif strcmp(name, 'relop3')
        tgt = rTB_relop3;
    else
        continue;
    end
    try; slreq.createLink(get_param(blk{1},'Handle'), tgt); totalLinks=totalLinks+1; catch e; warning('%s',e.message); end
end

% Logic (NOR) → rTB_LogicOp
for blk = find_system(toBoolPath, 'SearchDepth', 1, 'BlockType', 'Logic')'
    try; slreq.createLink(get_param(blk{1},'Handle'), rTB_LogicOp); totalLinks=totalLinks+1; catch e; warning('%s',e.message); end
end

%% ── disabled ─────────────────────────────────────────────────────────

for blk = find_system(disPath, 'SearchDepth', 1, 'BlockType', 'Constant')'
    try; slreq.createLink(get_param(blk{1},'Handle'), rDis_Const); totalLinks=totalLinks+1; catch e; warning('%s',e.message); end
end

%% ── targetSpeed ──────────────────────────────────────────────────────

for blk = find_system(tsPath, 'SearchDepth', 1, 'BlockType', 'UnitDelay')'
    try; slreq.createLink(get_param(blk{1},'Handle'), rTS_UD1); totalLinks=totalLinks+1; catch e; warning('%s',e.message); end
end

for blk = find_system(tsPath, 'SearchDepth', 1, 'BlockType', 'Logic')'
    try; slreq.createLink(get_param(blk{1},'Handle'), rTS_Logic); totalLinks=totalLinks+1; catch e; warning('%s',e.message); end
end

for blk = find_system(tsPath, 'SearchDepth', 1, 'BlockType', 'Switch')'
    try; slreq.createLink(get_param(blk{1},'Handle'), rTS_Sw5); totalLinks=totalLinks+1; catch e; warning('%s',e.message); end
end

%% ── getNewTargetSpeed ────────────────────────────────────────────────

% EnumConst（SubSystem）→ 値で振り分け
for blk = find_system(gntsPath, 'SearchDepth', 1, 'BlockType', 'SubSystem')'
    try
        vals = get_param(blk{1}, 'MaskValues');
        enumVal = vals{2};
        if contains(enumVal, 'Activate')
            tgt = rGNTS_EC_Act;
        elseif contains(enumVal, 'IncrementHold')
            tgt = rGNTS_EC_IncH;
        elseif strcmp(enumVal, 'opMode.Increment')
            tgt = rGNTS_EC_Inc;
        elseif contains(enumVal, 'Decrement')
            tgt = rGNTS_EC_Dec;
        else
            continue;
        end
        slreq.createLink(get_param(blk{1}, 'Handle'), tgt);
        totalLinks = totalLinks + 1;
    catch
    end
end

% Constant → 名前で振り分け
for blk = find_system(gntsPath, 'SearchDepth', 1, 'BlockType', 'Constant')'
    name = get_param(blk{1}, 'Name');
    if strcmp(name, 'Constant')
        tgt = rGNTS_C_inc_s;
    elseif strcmp(name, 'Constant1')
        tgt = rGNTS_C_inc_h;
    elseif strcmp(name, 'Constant2')
        tgt = rGNTS_C_dec_s;
    elseif strcmp(name, 'Constant3')
        tgt = rGNTS_C_dec_h;
    else
        continue;
    end
    try; slreq.createLink(get_param(blk{1},'Handle'), tgt); totalLinks=totalLinks+1; catch e; warning('%s',e.message); end
end

% Sum (Add1~4) → 名前で振り分け
for blk = find_system(gntsPath, 'SearchDepth', 1, 'BlockType', 'Sum')'
    name = get_param(blk{1}, 'Name');
    if strcmp(name, 'Add1')
        tgt = rGNTS_Add1;
    elseif strcmp(name, 'Add2')
        tgt = rGNTS_Add2;
    elseif strcmp(name, 'Add3')
        tgt = rGNTS_Add3;
    elseif strcmp(name, 'Add4')
        tgt = rGNTS_Add4;
    else
        continue;
    end
    try; slreq.createLink(get_param(blk{1},'Handle'), tgt); totalLinks=totalLinks+1; catch e; warning('%s',e.message); end
end

% RelationalOperator → 名前末尾の数字で振り分け
for blk = find_system(gntsPath, 'SearchDepth', 1, 'BlockType', 'RelationalOperator')'
    name = get_param(blk{1}, 'Name');
    if endsWith(name, '1')
        tgt = rGNTS_RelOp1;
    elseif endsWith(name, '2')
        tgt = rGNTS_RelOp2;
    elseif endsWith(name, '3')
        tgt = rGNTS_RelOp3;
    elseif endsWith(name, '4')
        tgt = rGNTS_RelOp4;
    else
        continue;
    end
    try; slreq.createLink(get_param(blk{1},'Handle'), tgt); totalLinks=totalLinks+1; catch e; warning('%s',e.message); end
end

% Switch → 名前で振り分け（Switchのみの名前がActivate保持）
for blk = find_system(gntsPath, 'SearchDepth', 1, 'BlockType', 'Switch')'
    name = get_param(blk{1}, 'Name');
    if strcmp(name, 'Switch')
        tgt = rGNTS_Sw;
    elseif strcmp(name, 'Switch1')
        tgt = rGNTS_Sw1;
    elseif strcmp(name, 'Switch2')
        tgt = rGNTS_Sw2;
    elseif strcmp(name, 'Switch3')
        tgt = rGNTS_Sw3;
    else
        continue;
    end
    try; slreq.createLink(get_param(blk{1},'Handle'), tgt); totalLinks=totalLinks+1; catch e; warning('%s',e.message); end
end

% Saturate → rGNTS_Sat
for blk = find_system(gntsPath, 'SearchDepth', 1, 'BlockType', 'Saturate')'
    try; slreq.createLink(get_param(blk{1},'Handle'), rGNTS_Sat); totalLinks=totalLinks+1; catch e; warning('%s',e.message); end
end

%% ── PI controller ────────────────────────────────────────────────────

for blk = find_system(piPath, 'SearchDepth', 1, 'BlockType', 'Sum')'
    name = get_param(blk{1}, 'Name');
    if strcmp(strtrim(name), 'Add')
        tgt = rPI_Add;
    elseif strcmp(strtrim(name), 'Sum')
        tgt = rPI_Sum;
    else
        continue;
    end
    try; slreq.createLink(get_param(blk{1},'Handle'), tgt); totalLinks=totalLinks+1; catch e; warning('%s',e.message); end
end

for blk = find_system(piPath, 'SearchDepth', 1, 'BlockType', 'DiscreteIntegrator')'
    try; slreq.createLink(get_param(blk{1},'Handle'), rPI_DTI); totalLinks=totalLinks+1; catch e; warning('%s',e.message); end
end

for blk = find_system(piPath, 'SearchDepth', 1, 'BlockType', 'Gain')'
    try; slreq.createLink(get_param(blk{1},'Handle'), rPI_Kp); totalLinks=totalLinks+1; catch e; warning('%s',e.message); end
end

%% ── UsePI ────────────────────────────────────────────────────────────

% RelationalOperator → 名前で振り分け
for blk = find_system(usepiPath, 'SearchDepth', 1, 'BlockType', 'RelationalOperator')'
    name = get_param(blk{1}, 'Name');
    if strcmp(strtrim(name), 'relop')
        tgt = rUPI_relop_sp;   % targetSpIn > vehSp
    else                        % 'Relational\nOperator': throtPI >= throtDrv
        tgt = rUPI_relop_th;
    end
    try; slreq.createLink(get_param(blk{1},'Handle'), tgt); totalLinks=totalLinks+1; catch e; warning('%s',e.message); end
end

% Logic (AND) → rUPI_Logic
for blk = find_system(usepiPath, 'SearchDepth', 1, 'BlockType', 'Logic')'
    try; slreq.createLink(get_param(blk{1},'Handle'), rUPI_Logic); totalLinks=totalLinks+1; catch e; warning('%s',e.message); end
end

%% ── getThrottleValue ─────────────────────────────────────────────────

for blk = find_system(gtvPath, 'SearchDepth', 1, 'BlockType', 'Delay')'
    try; slreq.createLink(get_param(blk{1},'Handle'), rGTV_Delay1); totalLinks=totalLinks+1; catch e; warning('%s',e.message); end
end

for blk = find_system(gtvPath, 'SearchDepth', 1, 'BlockType', 'Switch')'
    try; slreq.createLink(get_param(blk{1},'Handle'), rGTV_Sw); totalLinks=totalLinks+1; catch e; warning('%s',e.message); end
end

for blk = find_system(gtvPath, 'SearchDepth', 1, 'BlockType', 'Saturate')'
    try; slreq.createLink(get_param(blk{1},'Handle'), rGTV_Sat); totalLinks=totalLinks+1; catch e; warning('%s',e.message); end
end

%% ── TargetSpeedThrottle トップレベル ────────────────────────────────

for blk = find_system(tstPath, 'SearchDepth', 1, 'BlockType', 'Merge')'
    name = get_param(blk{1}, 'Name');
    if strcmp(name, 'Merge')
        tgt = rMerge;
    elseif strcmp(name, 'Merge1')
        tgt = rMerge1;
    else
        continue;
    end
    try; slreq.createLink(get_param(blk{1},'Handle'), tgt); totalLinks=totalLinks+1; catch e; warning('%s',e.message); end
end

for blk = find_system(tstPath, 'SearchDepth', 1, 'BlockType', 'UnitDelay')'
    try; slreq.createLink(get_param(blk{1},'Handle'), rUD); totalLinks=totalLinks+1; catch e; warning('%s',e.message); end
end

%% ── 保存 ─────────────────────────────────────────────────────────────

linkSets = slreq.find('Type', 'LinkSet');
for i = 1:numel(linkSets)
    save(linkSets(i));
end
save(rs);

fprintf('Done. Requirements added and %d Implement links created.\n', totalLinks);
