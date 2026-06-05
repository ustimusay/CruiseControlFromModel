%% generate_CruiseControlMode_MCDC_report.m
%  CruiseControlMode MCDC テストトレーサビリティレポートを PDF で生成する
%  generate_mcdc_report.m の汎用関数を利用して設定を渡す。

demoDir     = currentProject().RootFolder;
harnessName = 'CCMode_MCDC_Probe';

cfg = struct();
cfg.subsystemLabel  = 'CruiseControlMode';
cfg.demoDir         = demoDir;
cfg.modelName       = 'crs_controller';
cfg.testFilePath    = fullfile(demoDir, 'tests', 'CruiseControlMode_MCDC_Tests.mldatx');
cfg.suiteName       = 'CruiseControlMode_MCDC_Suite';
cfg.inputsDir       = fullfile(demoDir, 'tests', 'test_inputs_ccm');
cfg.baselinesDir    = fullfile(demoDir, 'tests', 'baselines_ccm');
cfg.reportDir       = fullfile(demoDir, 'reports', 'report_ccm_mcdc');
cfg.reportFileName  = 'CruiseControlMode_MCDC_report.pdf';
cfg.reportTitle     = 'CruiseControlMode MCDC';
cfg.reportSubtitle  = 'テストトレーサビリティレポート';
cfg.chapterTitle    = 'CruiseControlMode MCDC テストケース（TC01 〜 TC46, TC48 〜 TC49）';
cfg.reqFilePath     = fullfile(demoDir, 'crs_controller_requirements.slreqx');
cfg.harnessName     = harnessName;
cfg.harnessOwner    = 'crs_controller/CruiseControlMode';
cfg.skipTestRun     = true;
cfg.reuseWaveforms  = true;
cfg.reuseSlicerImages = true;
cfg.openReport      = false;
cfg.slicerStartPt   = [harnessName '/CruiseControlMode/mode'];
cfg.slicerLevels    = {
    'CruiseControlMode',    [harnessName '/CruiseControlMode'];
    'opMode',               [harnessName '/CruiseControlMode/opMode'];
    'disableCaseDetection', [harnessName '/CruiseControlMode/disableCaseDetection'];
    'getActStatus',         [harnessName '/CruiseControlMode/getActStatus'];
    'outOfRange',           [harnessName '/CruiseControlMode/outOfRange'];
};

% ── 入力信号設定 ─────────────────────────────────────────────────────────
reqDrvLabels = {'NoReq','Cancel','Cruise','Set','Resume', ...
                'Inc\_S','Inc\_M','Inc\_L','Dec\_S','Dec\_M','Dec\_L'};
cfg.inputSignals = {
    struct('name','reqDrv','color',[0.10 0.45 0.85], ...
           'yLim',[-0.5 10.5],'yTicks',0:10,'yLabels',{reqDrvLabels});
    struct('name','brakeP','color',[0.85 0.33 0.10], ...
           'yLim',[],'yTicks',[],'yLabels',{{}});
    struct('name','vehSp', 'color',[0.85 0.70 0.10], ...
           'yLim',[],'yTicks',[],'yLabels',{{}});
    struct('name','key',   'color',[0.20 0.63 0.17], ...
           'yLim',[0.5 2.5],'yTicks',[1 2],'yLabels',{{'Off','On'}});
    struct('name','gear',  'color',[0.50 0.18 0.56], ...
           'yLim',[0.5 2.5],'yTicks',[1 2],'yLabels',{{'Park','Drive'}});
    struct('name','frontDistance','color',[0.30 0.30 0.30], ...
           'yLim',[],'yTicks',[],'yLabels',{{}});
};

% ── 出力信号設定 ─────────────────────────────────────────────────────────
% Elem[1]=status(logical), Elem[2]=mode(opMode: 0=Disable,1=Enable,2=Activate,
%   3=Resume,4=Increment,5=IncrHold,6=Decrement,7=DecrHold)
opModeLabels = {'Disable','Enable','Activate','Resume', ...
                'Increment','IncrHold','Decrement','DecrHold'};
cfg.outputSignals = {
    struct('elemIdx',1,'name','status','color',[0.78 0.08 0.08], ...
           'yLim',[-0.2 1.2],'yTicks',[0 1],'yLabels',{{'false','true'}}, ...
           'plotTitle','期待出力 status（赤: logical）');
    struct('elemIdx',2,'name','mode',  'color',[0.00 0.40 0.70], ...
           'yLim',[-0.5 7.5],'yTicks',0:7,'yLabels',{opModeLabels}, ...
           'plotTitle','期待出力 mode（青: opMode）');
};

generate_mcdc_report(cfg);
