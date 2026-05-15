%% generate_DriverSwRequest_MCDC_report.m
%  DriverSwRequest MCDC テストトレーサビリティレポートを PDF で生成する
%  generate_mcdc_report.m の汎用関数を利用して設定を渡す。

demoDir = currentProject().RootFolder;
harnessName = 'DriverSwRequest_MCDC_Harness';

cfg = struct();
cfg.subsystemLabel  = 'DriverSwRequest';
cfg.demoDir         = demoDir;
cfg.modelName       = 'crs_controller';
cfg.testFilePath    = fullfile(demoDir, 'tests', 'DriverSwRequest_MCDC_Tests.mldatx');
cfg.suiteName       = 'DriverSwRequest_MCDC_Suite';
cfg.inputsDir       = fullfile(demoDir, 'tests', 'test_inputs');
cfg.baselinesDir    = fullfile(demoDir, 'tests', 'baselines');
cfg.reportDir       = fullfile(demoDir, 'reports', 'report_dsr_mcdc');
cfg.reportFileName  = 'DriverSwRequest_MCDC_report.pdf';
cfg.reportTitle     = 'DriverSwRequest MCDC';
cfg.reportSubtitle  = 'テストトレーサビリティレポート';
cfg.chapterTitle    = 'DriverSwRequest MCDC テストケース（TC01 〜 TC32）';
cfg.reqFilePath     = fullfile(demoDir, 'crs_controller_requirements.slreqx');
cfg.harnessName     = harnessName;
cfg.harnessOwner    = 'crs_controller/DriverSwRequest';
cfg.slicerStartPt   = [harnessName '/DriverSwRequest/reqDrv'];
cfg.slicerLevels    = {
    'DriverSwRequest', [harnessName '/DriverSwRequest'];
    'decrement',       [harnessName '/DriverSwRequest/decrement'];
    'doNotRepeat',     [harnessName '/DriverSwRequest/doNot Repeat'];
    'increment',       [harnessName '/DriverSwRequest/increment'];
};

% 入力信号設定（全 boolean 0/1）
sigNames = {'enbl','cncl','set','resume','inc','dec'};
colors   = {[0.10 0.45 0.85],[0.85 0.33 0.10],[0.85 0.70 0.10], ...
            [0.20 0.63 0.17],[0.50 0.18 0.56],[0.64 0.08 0.18]};
cfg.inputSignals = cell(numel(sigNames),1);
for k = 1:numel(sigNames)
    cfg.inputSignals{k} = struct('name',sigNames{k},'color',colors{k}, ...
        'yLim',[-0.2 1.2],'yTicks',[0 1],'yLabels',{{'0','1'}});
end

% 出力信号設定
reqDrvLabels = {'NoReq','Cancel','Cruise','Set','Resume', ...
                'Inc\_S','Inc\_M','Inc\_L','Dec\_S','Dec\_M','Dec\_L'};
cfg.outputSignals = { struct('elemIdx',1,'name','reqDrv', ...
    'color',[0.78 0.08 0.08],'yLim',[-0.5 10.5], ...
    'yTicks',0:10,'yLabels',{reqDrvLabels},'plotTitle','期待出力 reqDrv（赤: 出力）') };

generate_mcdc_report(cfg);
