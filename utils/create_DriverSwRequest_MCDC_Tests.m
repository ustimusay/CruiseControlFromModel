%% create_DriverSwRequest_MCDC_Tests.m
% DriverSwRequest サブシステムの MCDC 100% カバレッジを達成する
% テストスイートを Simulink Test Manager 形式で作成する。
%
% カバー対象の決定/条件:
%   [優先スイッチ]  Switch(cncl), Switch1(enbl), Switch2(set), Switch3(resume)
%   [doNot Repeat]  LogicOp3=OR(Cancel,Cruise,Set,ResumeReq),
%                   relop4=(reqDrv==prev), LogicOp1=AND(LogicOp3,relop4)
%   [decrement]     Switch1(dec_sw), LogicOp3=OR(prev==Dec_Short,Dec_Middle),
%                   LogicOp1=AND(LogicOp3,dec_sw),
%                   relop_hold_long=(prev==Dec_Long),
%                   LogicOp_hold_long=AND(relop_hold_long,dec_sw),
%                   Switch_hold_long, Switch4(counter>=50), Switch6
%   [increment]     increment は decrement と対称

Ts  = 0.01;
COUNT_VAL = 50;       % SLDV counter CountValue
N_SHT = 6;           % 短いテスト (6ステップ)
N_LNG = COUNT_VAL + 8; % 長押しテスト (58ステップ)

rootDir      = currentProject().RootFolder;
outDir       = fullfile(rootDir, 'tests', 'test_inputs');
baselineDir  = fullfile(rootDir, 'tests', 'baselines');
testFile     = fullfile(rootDir, 'tests', 'DriverSwRequest_MCDC_Tests.mldatx');

if ~exist(outDir,      'dir'), mkdir(outDir);      end
if ~exist(baselineDir, 'dir'), mkdir(baselineDir); end

% ---- 入力ベクトル生成ヘルパー --------------------------------
function v = pulse(N, from, to)
    % from〜toステップ(1-indexed)だけ1、それ以外0
    v = zeros(N, 1);
    v(from:min(to,N)) = 1;
end

function matPath = saveMat(outDir, name, N, Ts, enbl, cncl, set_sw, resume, inc, dec)
    t = (0:N-1)' * Ts;
    % boolean Inports require logical timeseries
    function ts = boolTs(v, nm)
        ts = timeseries(logical(pad0(v,N)), t, 'Name', nm);
        ts.DataInfo.Interpolation = tsdata.interpolation('zoh');
    end
    enbl   = boolTs(enbl,   'enbl');   %#ok<NASGU>
    cncl   = boolTs(cncl,   'cncl');   %#ok<NASGU>
    set    = boolTs(set_sw, 'set');    %#ok<NASGU>
    resume = boolTs(resume, 'resume'); %#ok<NASGU>
    inc    = boolTs(inc,    'inc');    %#ok<NASGU>
    dec    = boolTs(dec,    'dec');    %#ok<NASGU>
    matPath = fullfile(outDir, [name '.mat']);
    save(matPath, 'enbl','cncl','set','resume','inc','dec');
end

function v = pad0(v, N)
    v = double(v(:));
    if numel(v) < N, v(end+1:N) = 0; end
    v = v(1:N);
end

% ---- テストファイル作成 --------------------------------------
sltest.testmanager.clear();
if exist(testFile, 'file'), delete(testFile); end
tf = sltest.testmanager.TestFile(testFile);

% TestFile レベルでカバレッジを有効化（スイートより先に設定必要）
tfCov = tf.getCoverageSettings();
tfCov.RecordCoverage = true;
tfCov.MetricSettings = 'dcm';   % d=decision, c=condition, m=MCDC

ts = sltest.testmanager.TestSuite(tf, 'DriverSwRequest_MCDC_Suite');

% TestSuite レベル: RecordCoverage のみ設定可（MetricSettings はファイルレベルのみ）
covSet = ts.getCoverageSettings();
covSet.RecordCoverage = true;

% ---- テストケース追加ヘルパー ---------------------------------
function tc = addTC(ts, name, desc, N, Ts, matPath)
    % 'baseline' タイプ: 期待値（ベースライン）との比較で合否判定
    tc = sltest.testmanager.TestCase(ts, 'baseline', name);
    tc.Description = desc;
    tc.setProperty('Model', 'crs_controller');
    tc.setProperty('HarnessOwner', 'crs_controller/DriverSwRequest', ...
                   'HarnessName',  'DriverSwRequest_MCDC_Harness');
    tc.setProperty('StopTime', (N-1)*Ts);
    tc.addInput(matPath, 'CreateIterations', false);
end

% ==============================================================
%  Group 1: 優先スイッチ MCDC
% ==============================================================
% TC01: 全入力0 → NoRequest (全スイッチの false パス)
p = saveMat(outDir,'TC01_NoInput',N_SHT,Ts, 0,0,0,0,0,0);
addTC(ts,'TC01_NoInput','全入力0: NoRequest（全Switchのfalseパス）',N_SHT,Ts,p);

% TC02: cncl のみ → Cancel (Switch true パス)
p = saveMat(outDir,'TC02_Cancel',N_SHT,Ts, 0,pulse(N_SHT,2,2),0,0,0,0);
addTC(ts,'TC02_Cancel','cncl=1: Cancel出力（Switch trueパス）',N_SHT,Ts,p);

% TC03: enbl のみ → Cruise (Switch1 true パス)
p = saveMat(outDir,'TC03_Cruise',N_SHT,Ts, pulse(N_SHT,2,2),0,0,0,0,0);
addTC(ts,'TC03_Cruise','enbl=1: Cruise出力（Switch1 trueパス）',N_SHT,Ts,p);

% TC04: set のみ → Set (Switch2 true パス)
p = saveMat(outDir,'TC04_Set',N_SHT,Ts, 0,0,pulse(N_SHT,2,2),0,0,0);
addTC(ts,'TC04_Set','set=1: Set出力（Switch2 trueパス）',N_SHT,Ts,p);

% TC05: resume のみ → ResumeReq (Switch3 true パス)
p = saveMat(outDir,'TC05_Resume',N_SHT,Ts, 0,0,0,pulse(N_SHT,2,2),0,0);
addTC(ts,'TC05_Resume','resume=1: ResumeReq出力（Switch3 trueパス）',N_SHT,Ts,p);

% ==============================================================
%  Group 2: 優先度競合テスト (MCDC 各スイッチ独立性)
% ==============================================================
% TC06: cncl=1,enbl=1 → Cancel (cncl > enbl)
p = saveMat(outDir,'TC06_PriorCncl',N_SHT,Ts, pulse(N_SHT,2,2),pulse(N_SHT,2,2),0,0,0,0);
addTC(ts,'TC06_PriorCncl','cncl+enbl同時: cncl優先でCancel',N_SHT,Ts,p);

% TC07: enbl=1,set=1 → Cruise (enbl > set)
p = saveMat(outDir,'TC07_PriorEnbl',N_SHT,Ts, pulse(N_SHT,2,2),0,pulse(N_SHT,2,2),0,0,0);
addTC(ts,'TC07_PriorEnbl','enbl+set同時: enbl優先でCruise',N_SHT,Ts,p);

% TC08: set=1,resume=1 → Set (set > resume)
p = saveMat(outDir,'TC08_PriorSet',N_SHT,Ts, 0,0,pulse(N_SHT,2,2),pulse(N_SHT,2,2),0,0);
addTC(ts,'TC08_PriorSet','set+resume同時: set優先でSet',N_SHT,Ts,p);

% TC09: resume=1,inc=1 → ResumeReq (resume > inc)
p = saveMat(outDir,'TC09_PriorResume',N_SHT,Ts, 0,0,0,pulse(N_SHT,2,2),pulse(N_SHT,2,2),0);
addTC(ts,'TC09_PriorResume','resume+inc同時: resume優先でResumeReq',N_SHT,Ts,p);

% ==============================================================
%  Group 3: doNot Repeat MCDC
% ==============================================================
% TC10: cncl 2サイクル → Cancel, NoRequest (LogicOp3 Cancel条件=true, AND=true)
p = saveMat(outDir,'TC10_CnclRepeat',N_SHT,Ts, 0,pulse(N_SHT,2,3),0,0,0,0);
addTC(ts,'TC10_CnclRepeat','cncl 2サイクル: Cancel→NoRequest（doNot Repeat AND=true, Cancel条件）',N_SHT,Ts,p);

% TC11: enbl 2サイクル → Cruise, NoRequest (Cruise条件独立)
p = saveMat(outDir,'TC11_CruiseRepeat',N_SHT,Ts, pulse(N_SHT,2,3),0,0,0,0,0);
addTC(ts,'TC11_CruiseRepeat','enbl 2サイクル: Cruise→NoRequest（Cruise条件独立）',N_SHT,Ts,p);

% TC12: set 2サイクル → Set, NoRequest (Set条件独立)
p = saveMat(outDir,'TC12_SetRepeat',N_SHT,Ts, 0,0,pulse(N_SHT,2,3),0,0,0);
addTC(ts,'TC12_SetRepeat','set 2サイクル: Set→NoRequest（Set条件独立）',N_SHT,Ts,p);

% TC13: resume 2サイクル → ResumeReq, NoRequest (ResumeReq条件独立)
p = saveMat(outDir,'TC13_ResumeRepeat',N_SHT,Ts, 0,0,0,pulse(N_SHT,2,3),0,0);
addTC(ts,'TC13_ResumeRepeat','resume 2サイクル: ResumeReq→NoRequest（ResumeReq条件独立）',N_SHT,Ts,p);

% TC14: inc 3サイクル → Inc_Short,Inc_Middle,Inc_Middle (LogicOp3=false→反復抑制なし)
p = saveMat(outDir,'TC14_IncNoSuppress',N_SHT,Ts, 0,0,0,0,pulse(N_SHT,2,4),0);
addTC(ts,'TC14_IncNoSuppress','inc 3サイクル継続: Inc反復抑制なし（doNot Repeat LogicOp3=false）',N_SHT,Ts,p);

% ==============================================================
%  Group 4: decrement サブシステム MCDC
% ==============================================================
% TC15: dec 1サイクル → Dec_Short (Switch1 true, LogicOp3=false)
p = saveMat(outDir,'TC15_DecShort',N_SHT,Ts, 0,0,0,0,0,pulse(N_SHT,2,2));
addTC(ts,'TC15_DecShort','dec 1サイクル: Dec_Short（Switch1 trueパス, LogicOp3=false）',N_SHT,Ts,p);

% TC16: dec 0 (Switch1 false パス)
p = saveMat(outDir,'TC16_DecOff',N_SHT,Ts, 0,0,0,0,0,0);
addTC(ts,'TC16_DecOff','dec=0: NoRequest（Switch1 falseパス）',N_SHT,Ts,p);

% TC17: dec 2サイクル → Dec_Short,Dec_Middle
% (LogicOp3: prev==Dec_Short true; LogicOp1=AND true)
p = saveMat(outDir,'TC17_DecMiddle_fromShort',N_SHT,Ts, 0,0,0,0,0,pulse(N_SHT,2,3));
addTC(ts,'TC17_DecMiddle_fromShort','dec 2サイクル: Dec_Short→Dec_Middle（LogicOp3 relop_short=true）',N_SHT,Ts,p);

% TC18: dec 3サイクル → Dec_Short,Dec_Middle,Dec_Middle
% (LogicOp3: prev==Dec_Middle true 独立; relop_short=false)
p = saveMat(outDir,'TC18_DecMiddle_fromMiddle',N_SHT,Ts, 0,0,0,0,0,pulse(N_SHT,2,4));
addTC(ts,'TC18_DecMiddle_fromMiddle','dec 3サイクル: Dec_Middle継続（LogicOp3 relop_middle=true 独立）',N_SHT,Ts,p);

% TC19: dec 1サイクル後リリース → Dec_Short,NoRequest
% (LogicOp1: LogicOp3=true だが dec_sw=false → AND=false)
decVec19 = [zeros(1,1); ones(2,1); zeros(N_SHT-3,1)];  % [0,1,0,0,0,0]
p = saveMat(outDir,'TC19_DecMiddle_LogicFalse',N_SHT,Ts, 0,0,0,0,0,decVec19);
addTC(ts,'TC19_DecMiddle_LogicFalse','dec押して即リリース: LogicOp1=false（LogicOp3=true,dec_sw=false）',N_SHT,Ts,p);

% TC20: dec COUNT_VAL サイクル → ... Dec_Long (counter fires, Switch4=true)
p = saveMat(outDir,'TC20_DecLong_Counter',N_LNG,Ts, 0,0,0,0,0,pulse(N_LNG,2,COUNT_VAL+2));
addTC(ts,'TC20_DecLong_Counter',['dec ' num2str(COUNT_VAL) 'サイクル継続: Dec_Long（カウンタ到達, Switch4 true）'],N_LNG,Ts,p);

% TC21: dec COUNT_VAL+2 サイクル → stays Dec_Long (LogicOp_hold_long=true)
p = saveMat(outDir,'TC21_DecLong_Hold',N_LNG,Ts, 0,0,0,0,0,pulse(N_LNG,2,COUNT_VAL+4));
addTC(ts,'TC21_DecLong_Hold',['dec ' num2str(COUNT_VAL+3) 'サイクル: Dec_Long維持（LogicOp_hold_long=true）'],N_LNG,Ts,p);

% TC22: Dec_Long後にdec解放 → Dec_Long,NoRequest
% (relop_hold_long=true, dec_sw=false → LogicOp_hold_long=false)
decVec22 = [zeros(1,1); ones(COUNT_VAL+2,1); zeros(N_LNG-COUNT_VAL-3,1)];
p = saveMat(outDir,'TC22_DecLong_Release',N_LNG,Ts, 0,0,0,0,0,decVec22);
addTC(ts,'TC22_DecLong_Release','Dec_Long後にdec解放: LogicOp_hold_long=false（dec_sw=false）',N_LNG,Ts,p);

% TC23: dec=1, prev=NoRequest → Dec_Short (relop_hold_long false, counter=0)
% (Dec_Long でないとき → Switch_hold_long false パス)
p = saveMat(outDir,'TC23_DecShort_HoldFalse',N_SHT,Ts, 0,0,0,0,0,pulse(N_SHT,2,2));
addTC(ts,'TC23_DecShort_HoldFalse','dec 1サイクル: prev≠Dec_Long → Switch_hold_long falseパス',N_SHT,Ts,p);

% ==============================================================
%  Group 5: increment サブシステム MCDC (dec と対称)
% ==============================================================
% TC24: inc 1サイクル → Inc_Short
p = saveMat(outDir,'TC24_IncShort',N_SHT,Ts, 0,0,0,0,pulse(N_SHT,2,2),0);
addTC(ts,'TC24_IncShort','inc 1サイクル: Inc_Short（Switch1 trueパス）',N_SHT,Ts,p);

% TC25: inc=0 → NoRequest from increment (Switch1 false)
p = saveMat(outDir,'TC25_IncOff',N_SHT,Ts, 0,0,0,0,0,0);
addTC(ts,'TC25_IncOff','inc=0: increment Switch1 falseパス',N_SHT,Ts,p);

% TC26: inc 2サイクル → Inc_Short,Inc_Middle (LogicOp3 relop_short=true)
p = saveMat(outDir,'TC26_IncMiddle_fromShort',N_SHT,Ts, 0,0,0,0,pulse(N_SHT,2,3),0);
addTC(ts,'TC26_IncMiddle_fromShort','inc 2サイクル: Inc_Short→Inc_Middle（prev==Inc_Short）',N_SHT,Ts,p);

% TC27: inc 3サイクル → Inc_Middle維持 (LogicOp3 relop_middle=true 独立)
p = saveMat(outDir,'TC27_IncMiddle_fromMiddle',N_SHT,Ts, 0,0,0,0,pulse(N_SHT,2,4),0);
addTC(ts,'TC27_IncMiddle_fromMiddle','inc 3サイクル: Inc_Middle継続（prev==Inc_Middle）',N_SHT,Ts,p);

% TC28: inc押して即リリース (LogicOp1=false: LogicOp3=true, inc_sw=false)
incVec28 = [zeros(1,1); ones(2,1); zeros(N_SHT-3,1)];
p = saveMat(outDir,'TC28_IncLogic1_False',N_SHT,Ts, 0,0,0,0,incVec28,0);
addTC(ts,'TC28_IncLogic1_False','inc押してリリース: LogicOp1=false（LogicOp3=true,inc_sw=false）',N_SHT,Ts,p);

% TC29: inc COUNT_VAL サイクル → Inc_Long (counter fires)
p = saveMat(outDir,'TC29_IncLong_Counter',N_LNG,Ts, 0,0,0,0,pulse(N_LNG,2,COUNT_VAL+2),0);
addTC(ts,'TC29_IncLong_Counter',['inc ' num2str(COUNT_VAL) 'サイクル: Inc_Long（カウンタ到達）'],N_LNG,Ts,p);

% TC30: inc COUNT_VAL+2 サイクル → Inc_Long維持 (LogicOp_hold_long=true)
p = saveMat(outDir,'TC30_IncLong_Hold',N_LNG,Ts, 0,0,0,0,pulse(N_LNG,2,COUNT_VAL+4),0);
addTC(ts,'TC30_IncLong_Hold','inc長押し: Inc_Long維持（LogicOp_hold_long=true）',N_LNG,Ts,p);

% TC31: Inc_Long後にinc解放 (LogicOp_hold_long=false)
incVec31 = [zeros(1,1); ones(COUNT_VAL+2,1); zeros(N_LNG-COUNT_VAL-3,1)];
p = saveMat(outDir,'TC31_IncLong_Release',N_LNG,Ts, 0,0,0,0,incVec31,0);
addTC(ts,'TC31_IncLong_Release','Inc_Long後にinc解放: LogicOp_hold_long=false',N_LNG,Ts,p);

% TC32: inc=1, prev=NoRequest → Inc_Short (Switch_hold_long false)
p = saveMat(outDir,'TC32_IncShort_HoldFalse',N_SHT,Ts, 0,0,0,0,pulse(N_SHT,2,2),0);
addTC(ts,'TC32_IncShort_HoldFalse','inc 1サイクル: prev≠Inc_Long → Switch_hold_long falseパス',N_SHT,Ts,p);

% ---- 入力マッピング + ベースライン（期待値）キャプチャ --------
% 全 TC の入力をマップしてから baseline を取得（シミュレーション実行）
tcs_all = ts.getTestCases();
fprintf('\nMapping inputs and capturing baselines...\n');
open_system('C:\work\demos\CruiseControlFromModel\crs_controller.slx');
for i = 1:numel(tcs_all)
    inp = tcs_all(i).getInputs();
    if ~isempty(inp)
        inp(1).map();
    end
    blPath = fullfile(baselineDir, [tcs_all(i).Name '_expected.mat']);
    tcs_all(i).captureBaselineCriteria(blPath, false);
    fprintf('  [%02d] %s -> baseline captured\n', i, tcs_all(i).Name);
end

% ---- Save ----
tf.saveToFile();
fprintf('\n===== Test file saved =====\n');
fprintf('File: %s\n', testFile);
fprintf('Total test cases: %d\n', numel(tcs_all));
