%% create_TST_MCDC_Tests.m
% TargetSpeedThrottle サブシステムの MCDC 100% カバレッジを達成する
% テストスイートを Simulink Test Manager 形式で作成する。
%
% MCDC カバー対象の決定/条件:
%   [toBoolean]        relop1(Disable), relop2(Enable), relop3(Resume)
%                      LogicOp=NOR(relop1,relop2,relop3) → isActivated
%   [targetSpeed]      LogicOp1=AND(isEnabled, prev_isActivated)
%                      Switch5(resume)
%   [getNewTargetSpeed] RelOp2(Activate), RelOp1(Increment),
%                       RelOp3(IncrementHold), RelOp4(Decrement)
%                       Switch chain (Activate/Increment/IncrementHold/Decrement/DecrementHold)
%                       Saturation [tsp_min=40, tsp_max=100]
%   [UsePI]            relop(targetSpIn>vehSp), RelOp(throtPI>=throtDrv)
%                      LogicalOp=AND(RelOp,relop)
%   [getThrottleValue] Switch(UsePI), Saturation2 [0,100]

% ---- 定数定義 --------------------------------------------------------
Ts  = 0.01;
DIS = 0; EN = 1; ACT = 2; RES = 3;
INC = 4; INH = 5; DEC = 6; DEH = 7;

N_S  = 3;   % 短いテスト（3ステップ）
N_M  = 4;   % 中テスト（4ステップ）
N_L  = 5;   % 長いテスト（5ステップ）
N_HI = 63;  % Saturation上限テスト（Disable+Activate+Increment×61）

rootDir    = currentProject().RootFolder;
outDir     = fullfile(rootDir, 'tests', 'test_inputs_tst');
baselineDir= fullfile(rootDir, 'tests', 'baselines_tst');
testFile   = fullfile(rootDir, 'tests', 'TST_MCDC_Tests.mldatx');
harnessName= 'TST_MCDC_Harness';
ownPath    = 'crs_controller/TargetSpeedThrottle';

if ~isfolder(outDir),      mkdir(outDir);      end
if ~isfolder(baselineDir), mkdir(baselineDir); end

% ---- ハーネス作成 ----------------------------------------------------
open_system(fullfile(rootDir, 'crs_controller.slx'));
existing = sltest.harness.find(ownPath);
for i = 1:numel(existing)
    if strcmp(existing(i).name, harnessName)
        sltest.harness.delete(ownPath, harnessName);
        break;
    end
end
sltest.harness.create(ownPath, ...
    'Name',   harnessName, ...
    'Source', 'Inport', ...
    'Sink',   'Outport');
fprintf('Harness created: %s\n', harnessName);

% ハーネス出力信号のロギングを有効化（captureBaselineCriteria に必要）
sltest.harness.open(ownPath, harnessName);
% 出力ポートの src ポートハンドルに対して SDI ストリーミングをマーク
outBlks = find_system(harnessName, 'SearchDepth', 1, 'BlockType', 'Outport');
for i = 1:numel(outBlks)
    ph  = get_param(outBlks{i}, 'PortHandles');
    lh  = get_param(ph.Inport, 'Line');
    if lh > 0
        srcPh = get_param(lh, 'SrcPortHandle');
        Simulink.sdi.markSignalForStreaming(srcPh, 1);
    end
end
save_system(harnessName);
sltest.harness.close(ownPath, harnessName);
fprintf('Signal logging enabled on harness outputs.\n');

% ---- テストファイル作成 ----------------------------------------------
sltest.testmanager.clear();
if isfile(testFile), delete(testFile); end
tf = sltest.testmanager.TestFile(testFile);

tfCov = tf.getCoverageSettings();
tfCov.RecordCoverage = true;
tfCov.MetricSettings = 'dcm';

ts = sltest.testmanager.TestSuite(tf, 'TST_MCDC_Suite');
covSet = ts.getCoverageSettings();
covSet.RecordCoverage = true;

% ---- ヘルパー関数（MAT ファイル保存） --------------------------------
function matPath = saveMat(outDir, name, N, Ts, modeVec, vehSpVal, throtDrvVal)
    t = (0:N-1)' * Ts;
    % mode: opMode 列挙型 (IntEnumType → enum timeseries)
    mv = int32(modeVec(:));
    if numel(mv) < N, mv(end+1:N) = mv(end); end
    mv = opMode(mv);   % int32 → opMode enum
    mode = timeseries(mv, t, 'Name', 'mode');
    mode.DataInfo.Interpolation = tsdata.interpolation('zoh');
    % vehSp
    sv = vehSpVal .* ones(N,1);
    vehSp = timeseries(sv, t, 'Name', 'vehSp');
    vehSp.DataInfo.Interpolation = tsdata.interpolation('zoh');
    % throtDrv
    tv = throtDrvVal .* ones(N,1);
    throtDrv = timeseries(tv, t, 'Name', 'throtDrv');
    throtDrv.DataInfo.Interpolation = tsdata.interpolation('zoh');
    matPath = fullfile(outDir, [name '.mat']);
    save(matPath, 'mode', 'vehSp', 'throtDrv');
end

function tc = addTC(ts, name, desc, N, Ts, matPath, ownPath, harnessName)
    tc = sltest.testmanager.TestCase(ts, 'baseline', name);
    tc.Description = desc;
    tc.setProperty('Model', 'crs_controller');
    tc.setProperty('HarnessOwner', ownPath, 'HarnessName', harnessName);
    tc.setProperty('StopTime', (N-1)*Ts);
    tc.addInput(matPath, 'CreateIterations', false);
end

% ==================================================================
%  Group 1: toBoolean MCDC + Enable サブシステム
% ==================================================================

% TC01: mode=Disable → relop1=T, NOR→F(Disable), disabled enabled
p = saveMat(outDir,'TC01_Disable',N_S,Ts, [DIS,DIS,DIS], 50, 30);
addTC(ts,'TC01_Disable', ...
    'mode=Disable: relop1=T, NOR=F（Disable）, disabled subsystem, Merge, UnitDelay', ...
    N_S,Ts,p,ownPath,harnessName);

% TC02: mode=Enable → relop2=T, NOR→F(Enable), enabled enabled
p = saveMat(outDir,'TC02_Enable',N_S,Ts, [DIS,EN,EN], 60, 25);
addTC(ts,'TC02_Enable', ...
    'mode=Enable: relop2=T, NOR=F（Enable）, enabled subsystem', ...
    N_S,Ts,p,ownPath,harnessName);

% TC03: mode=Activate → NOR=T(all false), RelOp2=T, Switch-keep, UsePI=F(vehSp>targetSp)
p = saveMat(outDir,'TC03_Activate',N_S,Ts, [DIS,ACT,ACT], 50, 0);
addTC(ts,'TC03_Activate', ...
    'mode=Activate: NOR=T, RelOp2=T, Switch=T（targetSpIn保持）, UsePI=F(relop=F)', ...
    N_S,Ts,p,ownPath,harnessName);

% TC04: Activate→Enable→Resume → relop3=T, NOR→F(Resume), LogicOp1=T, Switch5=T
p = saveMat(outDir,'TC04_Resume',N_L,Ts, [DIS,ACT,EN,RES,RES], 50, 30);
addTC(ts,'TC04_Resume', ...
    'Activate→Enable→Resume: relop3=T, NOR=F（Resume）, LogicOp1=T（storeSpeed格納）, Switch5=T（resume=T）', ...
    N_L,Ts,p,ownPath,harnessName);

% ==================================================================
%  Group 2: targetSpeed/LogicOp1 MCDC（AND の独立条件）
% ==================================================================

% TC05: Enable→Enable → LogicOp1=F（prev_isActivated=F 独立）
p = saveMat(outDir,'TC05_LogicOp1_prevActFalse',N_S,Ts, [EN,EN,EN], 60, 25);
addTC(ts,'TC05_LogicOp1_prevActFalse', ...
    'Enable×3: LogicOp1=F（isEnabled=T, prev_isActivated=F → AND=F, prev_isActivated独立）', ...
    N_S,Ts,p,ownPath,harnessName);

% TC06: Activate→Disable → LogicOp1=F（isEnabled=F 独立）
p = saveMat(outDir,'TC06_LogicOp1_enFalse',N_M,Ts, [ACT,DIS,DIS,DIS], 50, 0);
addTC(ts,'TC06_LogicOp1_enFalse', ...
    'Activate→Disable: LogicOp1=F（isEnabled=F, prev_isActivated=T → AND=F, isEnabled独立）', ...
    N_M,Ts,p,ownPath,harnessName);

% ==================================================================
%  Group 3: getNewTargetSpeed Switch チェーン MCDC
% ==================================================================

% TC07: mode=Increment → RelOp2=F, RelOp1=T, Switch=F, Switch1=T, Add1実行
p = saveMat(outDir,'TC07_Increment',N_S,Ts, [DIS,ACT,INC], 50, 0);
addTC(ts,'TC07_Increment', ...
    'mode=Increment: RelOp1=T, Switch=F, Switch1=T, Add1(+1km/h)実行', ...
    N_S,Ts,p,ownPath,harnessName);

% TC08: mode=IncrementHold → RelOp1=F, RelOp3=T, Switch1=F, Switch2=T, Add2実行
p = saveMat(outDir,'TC08_IncrementHold',N_S,Ts, [DIS,ACT,INH], 50, 0);
addTC(ts,'TC08_IncrementHold', ...
    'mode=IncrementHold: RelOp3=T, Switch1=F, Switch2=T, Add2(+0.05km/h)実行', ...
    N_S,Ts,p,ownPath,harnessName);

% TC09: mode=Decrement → RelOp3=F, RelOp4=T, Switch2=F, Switch3=T, Add3実行
p = saveMat(outDir,'TC09_Decrement',N_M,Ts, [DIS,ACT,INC,DEC], 50, 0);
addTC(ts,'TC09_Decrement', ...
    'mode=Decrement: RelOp4=T, Switch2=F, Switch3=T, Add3(-1km/h)実行', ...
    N_M,Ts,p,ownPath,harnessName);

% TC10: mode=DecrementHold → RelOp4=F, Switch3=F, Add4実行（DecrementHold=else パス）
p = saveMat(outDir,'TC10_DecrementHold',N_M,Ts, [DIS,ACT,INC,DEH], 50, 0);
addTC(ts,'TC10_DecrementHold', ...
    'mode=DecrementHold: RelOp4=F, Switch3=F, Add4(-0.05km/h)実行', ...
    N_M,Ts,p,ownPath,harnessName);

% ==================================================================
%  Group 4: Saturation（getNewTargetSpeed）境界テスト
% ==================================================================

% TC11: Saturation 下限クランプ（Decrement from tsp_min → 39 → クランプ 40）
p = saveMat(outDir,'TC11_SatLow',N_S,Ts, [DIS,ACT,DEC], 50, 0);
addTC(ts,'TC11_SatLow', ...
    'Decrement from tsp_min(40): 39 → クランプ 40 km/h（Saturation 下限パス）', ...
    N_S,Ts,p,ownPath,harnessName);

% TC12: Saturation 上限クランプ（Increment×61 → 101 → クランプ 100 km/h）
modeHi = [DIS, ACT, repmat(INC, 1, N_HI-2)];
p = saveMat(outDir,'TC12_SatHigh',N_HI,Ts, modeHi, 50, 0);
addTC(ts,'TC12_SatHigh', ...
    sprintf('Increment×61: 101 → クランプ 100 km/h（Saturation 上限パス）, N=%d', N_HI), ...
    N_HI,Ts,p,ownPath,harnessName);

% ==================================================================
%  Group 5: UsePI MCDC + Saturation2 境界テスト
% ==================================================================

% TC13: UsePI=T (throtPI>=throtDrv AND targetSpIn>vehSp → 両方True)
%   k=1: UsePI=T, PI.out=0(Delay1=F), throtCC=0（Sat2 通過）
%   k=2: Delay1=T→PI有効, PI.out=200.1→Sat2上限クランプ100
p = saveMat(outDir,'TC13_UsePITrue',N_S,Ts, [DIS,ACT,ACT], 30, 0);
addTC(ts,'TC13_UsePITrue', ...
    'vehSp=30<targetSp=40, throtDrv=0: UsePI=T(relop=T,RelOp=T), PI有効, Sat2上限クランプ(100%)', ...
    N_S,Ts,p,ownPath,harnessName);

% TC14: UsePI=F, relop独立（targetSpIn NOT > vehSp）
%   k=1: 40>50=F → relop=F → AND=F → UsePI=F → throtCC=throtDrv=0
p = saveMat(outDir,'TC14_UsePI_relpFalse',N_S,Ts, [DIS,ACT,ACT], 50, 0);
addTC(ts,'TC14_UsePI_relpFalse', ...
    'vehSp=50>targetSp=40: relop=F → UsePI=F（relop独立）, Switch=F, throtCC=throtDrv', ...
    N_S,Ts,p,ownPath,harnessName);

% TC15: UsePI=F, RelOp独立（throtPI < throtDrv）
%   k=1: throtPI=0 < throtDrv=50 → RelOp=F → AND=F → UsePI=F → throtCC=50
p = saveMat(outDir,'TC15_UsePI_RelOpFalse',N_S,Ts, [DIS,ACT,ACT], 30, 50);
addTC(ts,'TC15_UsePI_RelOpFalse', ...
    'throtDrv=50>throtPI=0: RelOp=F → UsePI=F（RelOp独立）, Switch=F, throtCC=throtDrv=50', ...
    N_S,Ts,p,ownPath,harnessName);

% TC16: Saturation2 下限クランプ（UsePI=F, throtDrv=-5 → クランプ 0）
%   vehSp=50>targetSp=40→UsePI=F→throtDrv=-5→Sat2クランプ→0
p = saveMat(outDir,'TC16_Sat2Lower',N_S,Ts, [DIS,ACT,ACT], 50, -5);
addTC(ts,'TC16_Sat2Lower', ...
    'throtDrv=-5: UsePI=F→Switch→Sat2下限クランプ 0%（Saturation2 下限パス）', ...
    N_S,Ts,p,ownPath,harnessName);

% ==================================================================
%  入力マッピング + ベースライン（期待値）キャプチャ
% ==================================================================
tcs_all = ts.getTestCases();
fprintf('\nMapping inputs and capturing baselines...\n');
for i = 1:numel(tcs_all)
    inp = tcs_all(i).getInputs();
    if ~isempty(inp)
        inp(1).map();
    end
    blPath = fullfile(baselineDir, [tcs_all(i).Name '_expected.mat']);
    tcs_all(i).captureBaselineCriteria(blPath, false);
    fprintf('  [%02d] %s -> baseline captured\n', i, tcs_all(i).Name);
end

tf.saveToFile();
fprintf('\n===== Test file saved =====\n');
fprintf('File: %s\n', testFile);
fprintf('Total test cases: %d\n', numel(tcs_all));
