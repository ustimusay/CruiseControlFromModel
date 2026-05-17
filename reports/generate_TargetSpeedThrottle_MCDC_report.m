%% generate_TargetSpeedThrottle_MCDC_report.m
%  TargetSpeedThrottle MCDC テストトレーサビリティレポートを PDF で生成する
%  generate_mcdc_report.m の汎用関数を利用して設定を渡す。

demoDir     = currentProject().RootFolder;
harnessName = 'TST_MCDC_Harness';

cfg = struct();
cfg.subsystemLabel  = 'TargetSpeedThrottle';
cfg.demoDir         = demoDir;
cfg.modelName       = 'crs_controller';
cfg.testFilePath    = fullfile(demoDir, 'tests', 'TST_MCDC_Tests.mldatx');
cfg.suiteName       = 'TST_MCDC_Suite';
cfg.inputsDir       = fullfile(demoDir, 'tests', 'test_inputs_tst');
cfg.baselinesDir    = fullfile(demoDir, 'tests', 'baselines_tst');
cfg.reportDir       = fullfile(demoDir, 'reports', 'report_tst_mcdc');
cfg.reportFileName  = 'TargetSpeedThrottle_MCDC_report.pdf';
cfg.reportTitle     = 'TargetSpeedThrottle MCDC';
cfg.reportSubtitle  = 'テストトレーサビリティレポート';
cfg.chapterTitle    = 'TargetSpeedThrottle MCDC テストケース（TC01 〜 TC16）';
cfg.reqFilePath     = fullfile(demoDir, 'crs_controller_requirements.slreqx');
cfg.harnessName     = harnessName;
cfg.harnessOwner    = 'crs_controller/TargetSpeedThrottle';
cfg.slicerStartPt   = [harnessName '/TargetSpeedThrottle/throtCC'];
cfg.slicerLevels    = {
    'TargetSpeedThrottle',  [harnessName '/TargetSpeedThrottle'];
    'toBoolean',            [harnessName '/TargetSpeedThrottle/toBoolean'];
    'targetSpeed',          [harnessName '/TargetSpeedThrottle/targetSpeed'];
    'activated',            [harnessName '/TargetSpeedThrottle/activated'];
    'getNewTargetSpeed',    [harnessName '/TargetSpeedThrottle/activated/getNewTargetSpeed'];
    'getThrottleValue',     [harnessName '/TargetSpeedThrottle/activated/getThrottleValue'];
};

% ── 入力信号設定 ─────────────────────────────────────────────────────────
opModeLabels = {'Disable','Enable','Activate','Resume', ...
                'Increment','IncrHold','Decrement','DecrHold'};
cfg.inputSignals = {
    struct('name','mode',     'color',[0.10 0.45 0.85], ...
           'yLim',[-0.5 7.5],'yTicks',0:7,'yLabels',{opModeLabels});
    struct('name','vehSp',    'color',[0.85 0.33 0.10], ...
           'yLim',[],'yTicks',[],'yLabels',{{}});
    struct('name','throtDrv', 'color',[0.20 0.63 0.17], ...
           'yLim',[],'yTicks',[],'yLabels',{{}});
};

% ── 出力信号設定 ─────────────────────────────────────────────────────────
% Out1=targetSp (km/h, 40-100), Out2=throtCC (%, 0-100)
cfg.outputSignals = {
    struct('elemIdx',1,'name','targetSp','color',[0.78 0.08 0.08], ...
           'yLim',[35 105],'yTicks',40:10:100,'yLabels',{{}}, ...
           'plotTitle','期待出力 targetSp（赤: 目標速度 km/h）');
    struct('elemIdx',2,'name','throtCC', 'color',[0.00 0.40 0.70], ...
           'yLim',[-5 105],'yTicks',0:25:100,'yLabels',{{}}, ...
           'plotTitle','期待出力 throtCC（青: スロットル指令値 %）');
};

generate_mcdc_report(cfg);
