%% generate_DriverSwRequest_MCDC_report.m
%  DriverSwRequest MCDC テストトレーサビリティレポートを PDF で生成する
%
%  各 TC セクション:
%    1. テストケース情報・テスト結果
%    2. 紐づく要件 (ID / Summary / Description / Rationale)
%    3. 入力波形 + 期待出力 (reqDrv)
%    4. Model Slicer ハイライト (全 TC 共通の静的後向きスライス)
%       ・slsliceroptions.UseTimeWindow=true を設定
%       ・simulate() を呼ばず highlight() のみ → 静的構造スライス
%       ・Switch の全入力（NoRequest/Cancel/Cruise/Set/Resume 定数を含む）がハイライト対象
%       ・Starting point: crs_controller/DriverSwRequest/reqDrv
%       ・DriverSwRequest 4 レベルのスクリーンショット（全 TC 共通）
%
%  フェーズ分離:
%    Phase A: 全 32 TC 実行 → 結果・SDI 信号 ID 収集
%    Phase B: 全 TC 分の波形プロット生成
%    Phase C: 全 TC 分の Model Slicer ハイライト + スクリーンショット
%    Phase D: PDF 組み立て (mlreportgen)

demoDir      = currentProject().RootFolder;
inputsDir    = fullfile(demoDir, 'tests',   'test_inputs');
baselinesDir = fullfile(demoDir, 'tests',   'baselines');
imgDir       = fullfile(demoDir, 'reports', 'report_dsr_mcdc', 'imgs');
cvtDir       = fullfile(demoDir, 'reports', 'report_dsr_mcdc', 'cvt');
outFile      = fullfile(demoDir, 'reports', 'report_dsr_mcdc', 'DriverSwRequest_MCDC_report.pdf');

if ~exist(imgDir, 'dir'), mkdir(imgDir); end
if ~exist(cvtDir, 'dir'), mkdir(cvtDir); end

%% ── 1. モデル・テスト・要件 読み込み ─────────────────────────────────────
if ~bdIsLoaded('crs_controller')
    open_system(fullfile(demoDir, 'crs_controller.slx'));
end

slreq.clear();
rs = slreq.load(fullfile(demoDir, 'crs_controller_requirements.slreqx'));

existingFiles = sltest.testmanager.getTestFiles();
tfObj = [];
for i = 1:numel(existingFiles)
    if strcmp(existingFiles(i).Name, 'DriverSwRequest_MCDC_Tests')
        tfObj = existingFiles(i); break;
    end
end
if isempty(tfObj)
    tfObj = sltest.testmanager.load(fullfile(demoDir, 'tests', 'DriverSwRequest_MCDC_Tests.mldatx'));
end

% DriverSwRequest_MCDC_Suite を取得
suites    = tfObj.getTestSuites();
testSuite = [];
for i = 1:numel(suites)
    if strcmp(suites(i).Name, 'DriverSwRequest_MCDC_Suite')
        testSuite = suites(i); break;
    end
end
tcs = testSuite.getTestCases();
fprintf('Total test cases: %d\n', numel(tcs));

%% ── 2. UUID → TC オブジェクト マップ ────────────────────────────────────
tcObjMap = containers.Map();
for i = 1:numel(tcs)
    tcObjMap(tcs(i).UUID) = tcs(i);
end

%% ── 3. Verify リンクから UUID → {要件} マップを構築 ─────────────────────
tcUuidToReqs = containers.Map();  % UUID → {req, req, ...}
linkSets = slreq.find('Type', 'LinkSet');
for i = 1:numel(linkSets)
    lnks = linkSets(i).getLinks();
    for j = 1:numel(lnks)
        lnk = lnks(j);
        if ~strcmp(lnk.Type, 'Verify'), continue; end
        uuid  = lnk.source.id;       % TC UUID
        reqId = lnk.destination.id;  % '#1', '#4', ...
        try
            req = find(rs, 'Type', 'Requirement', 'Id', reqId);
            if ~isKey(tcUuidToReqs, uuid)
                tcUuidToReqs(uuid) = {};
            end
            tcUuidToReqs(uuid) = [tcUuidToReqs(uuid), {req}];
        catch
        end
    end
end
fprintf('TCs with requirement links: %d\n', tcUuidToReqs.Count);

%% ── 4. Model Slicer 対象サブシステム定義 ────────────────────────────────
% テストハーネス名 (DriverSwRequest_MCDC_Harness) を基点とするパス
harnessName  = 'DriverSwRequest_MCDC_Harness';
slicerLevels = {
    'DriverSwRequest',   [harnessName '/DriverSwRequest'];
    'decrement',         [harnessName '/DriverSwRequest/decrement'];
    'doNot Repeat',      [harnessName '/DriverSwRequest/doNot Repeat'];
    'increment',         [harnessName '/DriverSwRequest/increment'];
};

%% ══════════════════════════════════════════════════════════════════════════
%  Phase A: 全 TC 実行 + 結果・SDI 信号 ID 収集
%% ══════════════════════════════════════════════════════════════════════════
fprintf('\n=== Phase A: Running all test cases ===\n');

resultSet   = tfObj.run();
fileResArr  = resultSet.getTestFileResults();
suiteResArr = fileResArr(1).getTestSuiteResults();

mcdcSuiteRes = [];
for i = 1:numel(suiteResArr)
    if strcmp(suiteResArr(i).Name, 'DriverSwRequest_MCDC_Suite')
        mcdcSuiteRes = suiteResArr(i); break;
    end
end
tcResArr = mcdcSuiteRes.getTestCaseResults();

% TC名 → {Outcome, SigID} マップ
tcInfoMap = containers.Map();
for i = 1:numel(tcResArr)
    r = tcResArr(i);

    sigID = [];
    outRuns = r.getOutputRuns();
    if numel(outRuns) > 0
        sigIDs = outRuns(1).getAllSignalIDs();
        if numel(sigIDs) > 0
            sigID = sigIDs(1);
        end
    end

    if r.Outcome == 2, outcomeStr = 'Passed'; else, outcomeStr = 'Failed'; end

    tcInfoMap(r.Name) = struct('Outcome', outcomeStr, 'SigID', sigID);
    fprintf('  %-35s %s  (sigID=%s)\n', r.Name, outcomeStr, num2str(sigID));
end

%% ══════════════════════════════════════════════════════════════════════════
%  Phase B: 波形プロット (変化する入力 + 期待出力 reqDrv)
%% ══════════════════════════════════════════════════════════════════════════
fprintf('\n=== Phase B: Waveform plots ===\n');

inputSigNames = {'enbl','cncl','set','resume','inc','dec'};
inputColors   = {[0.10 0.45 0.85],[0.85 0.33 0.10],[0.85 0.70 0.10], ...
                 [0.20 0.63 0.17],[0.50 0.18 0.56],[0.64 0.08 0.18]};
reqDrvLabels  = {'NoReq','Cancel','Cruise','Set','Resume', ...
                 'Inc\_S','Inc\_M','Inc\_L','Dec\_S','Dec\_M','Dec\_L'};

for i = 1:numel(tcs)
    tcName  = tcs(i).Name;
    inpFile = fullfile(inputsDir,    [tcName '.mat']);
    blFile  = fullfile(baselinesDir, [tcName '_expected.mat']);

    inp = load(inpFile);
    bl  = load(blFile);
    blTS = bl.data.getElement(1).Values;

    % 変化する入力シグナルを抽出 (range > 0)
    changing = {};
    chColors  = {};
    for k = 1:numel(inputSigNames)
        d = squeeze(inp.(inputSigNames{k}).Data);
        if range(double(d)) > 0
            changing{end+1} = struct( ...
                'name', inputSigNames{k}, ...
                't',    inp.(inputSigNames{k}).Time, ...
                'd',    d);  %#ok<AGROW>
            chColors{end+1} = inputColors{k};  %#ok<AGROW>
        end
    end

    nIn    = numel(changing);
    nTotal = max(1, nIn) + 1;  % 入力行 + reqDrv 出力行

    fig = figure('Visible','off','Position',[100 100 920 max(280, nTotal*80)],'Color','w');

    % ── 入力サブプロット ──
    if nIn == 0
        ax = subplot(nTotal, 1, 1);
        text(0.5, 0.5, '(変化する入力なし — 全入力 = 0)', ...
            'HorizontalAlignment','center','FontSize',9,'Color',[0.4 0.4 0.4]);
        axis(ax,'off');
        title(ax, ['[' tcName '] 入力信号'], 'Interpreter','none','FontSize',9);
    else
        for k = 1:nIn
            ax = subplot(nTotal, 1, k);
            stairs(ax, changing{k}.t, double(changing{k}.d), ...
                'Color', chColors{k}, 'LineWidth', 1.5);
            ylabel(ax, changing{k}.name, 'Interpreter','none','FontSize',8, ...
                'Rotation',0,'HorizontalAlignment','right');
            ylim(ax,[-0.2 1.2]); yticks(ax,[0 1]);
            grid(ax,'on'); set(ax,'XTickLabel',{});
            ax.Color = [0.96 0.98 1.0];
            if k == 1
                title(ax, ['[' tcName '] 変化する入力信号（青系: 入力）'], ...
                    'Interpreter','none','FontSize',9);
            end
        end
    end

    % ── 期待出力 (reqDrv) ──
    ax = subplot(nTotal, 1, nTotal);
    t_bl = blTS.Time;
    d_bl = double(blTS.Data);
    stairs(ax, t_bl, d_bl, 'Color',[0.78 0.08 0.08],'LineWidth',2);
    ylim(ax,[-0.5 10.5]);
    yticks(ax,0:10); yticklabels(ax, reqDrvLabels);
    ylabel(ax,'reqDrv','FontSize',8,'Rotation',0,'HorizontalAlignment','right');
    xlabel(ax,'Time (s)','FontSize',8);
    grid(ax,'on');
    ax.Color = [1.0 0.96 0.96];
    title(ax,'期待出力 reqDrv（赤: 出力）','FontSize',8);

    saveas(fig, fullfile(imgDir, [tcName '_waveform.png']));
    close(fig);
    fprintf('  [%s]\n', tcName);
end

%% ══════════════════════════════════════════════════════════════════════════
%  Phase C: Model Slicer 動的スライス (UseTimeWindow=true + simulate)
%
%  DriverSwRequest_MCDC_Harness (6 boolean inport) を対象モデルとして使用。
%  crs_controller には 11 inport (型混在) があり Dataset のカウント/型チェックで
%  失敗するため、6 boolean inport のみのハーネスで simulate する。
%  CoverageFilter は使用しない。
%% ══════════════════════════════════════════════════════════════════════════
fprintf('\n=== Phase C: Model Slicer dynamic slice (UseTimeWindow=true + simulate) ===\n');

% crs_controller が開いていればハーネスを開く
if ~bdIsLoaded('crs_controller')
    open_system(fullfile(demoDir, 'crs_controller.slx'));
    drawnow; pause(1.0);
end

% ハーネスを開く (既に開いていれば再利用)
if ~bdIsLoaded(harnessName)
    sltest.harness.open('crs_controller/DriverSwRequest', harnessName);
    drawnow; pause(1.0);
end

for i = 1:numel(tcs)
    tcName = tcs(i).Name;
    sc = [];
    try
        % Test Manager の入力定義を取得
        tcInputs = tcs(i).getInputs();
        if isempty(tcInputs) || ~tcInputs(1).Active
            fprintf('  [%s] 入力定義なし — スキップ\n', tcName);
            continue;
        end
        tcInp    = tcInputs(1);
        inpFile  = tcInp.FilePath;
        sigNames = strtrim(strsplit(tcInp.InputString, ','));

        % .mat から timeseries をそのまま読み込んで Dataset に追加
        inpData = load(inpFile);
        stopT   = inpData.(sigNames{1}).Time(end);

        ds = Simulink.SimulationData.Dataset();
        for k = 1:numel(sigNames)
            vn = sigNames{k};
            ts = inpData.(vn);
            ts.Name = vn;
            ds = ds.addElement(ts, vn);
        end

        % ハーネスに対する SimulationInput を構築
        simIn = Simulink.SimulationInput(harnessName);
        simIn = simIn.setExternalInput(ds);
        simIn = simIn.setModelParameter('StopTime', num2str(stopT));

        % UseTimeWindow=true で動的スライサー生成 → simulate → highlight
        opts               = slsliceroptions();
        opts.UseTimeWindow = true;
        sc = slslicer(harnessName, opts);
        addStartingPoint(sc, [harnessName '/DriverSwRequest/reqDrv']);

        sc.simulate(simIn);
        sc.highlight();
        drawnow; pause(0.3);

        % 各サブシステムレベルのスクリーンショット (TC 固有ファイル名)
        for k = 1:size(slicerLevels, 1)
            label    = slicerLevels{k,1};
            fullPath = slicerLevels{k,2};
            open_system(fullPath, 'force');
            drawnow; pause(0.3);
            imgFile = fullfile(imgDir, [tcName '_slicer_' strrep(label,' ','') '.png']);
            print(['-s' fullPath], '-dpng', '-r120', imgFile);
        end

        delete(sc);
        sc = [];
        fprintf('  [%s] OK\n', tcName);

    catch e
        fprintf('  [%s] WARN: %s\n', tcName, e.message);
        if ~isempty(sc); try; delete(sc); catch; end; end
    end
end
fprintf('  Phase C complete.\n');

%% ══════════════════════════════════════════════════════════════════════════
%  Phase D: PDF 組み立て (mlreportgen)
%% ══════════════════════════════════════════════════════════════════════════
fprintf('\n=== Phase D: Building PDF ===\n');

import mlreportgen.report.*
import mlreportgen.dom.*

rpt         = Report(outFile, 'pdf');
tp          = TitlePage();
tp.Title    = 'DriverSwRequest MCDC';
tp.Subtitle = 'テストトレーサビリティレポート';
tp.Author   = sprintf('自動生成: %s', string(datetime('now'),'yyyy-MM-dd HH:mm'));
add(rpt, tp);
add(rpt, TableOfContents());

ch       = Chapter();
ch.Title = 'DriverSwRequest MCDC テストケース（TC01 〜 TC32）';

for i = 1:numel(tcs)
    tcName = tcs(i).Name;
    uuid   = tcs(i).UUID;

    % ── 結果 ──
    if isKey(tcInfoMap, tcName)
        outcomeStr = tcInfoMap(tcName).Outcome;
    else
        outcomeStr = 'Unknown';
    end
    outcomeColor = '#27ae60';  % green
    if ~strcmp(outcomeStr, 'Passed'), outcomeColor = '#e74c3c'; end

    % ── 紐づく要件 ──
    reqs = {};
    if isKey(tcUuidToReqs, uuid)
        reqs = tcUuidToReqs(uuid);
    end

    % ── Section ──
    sec       = Section();
    sec.Title = sprintf('%s  [%s]', tcName, outcomeStr);

    % ▼ テストケース情報
    add(sec, makeHeading('テストケース情報・テスト結果'));
    add(sec, makeTable2Col({
        'テストケース名', tcName;
        'テスト結果',    outcomeStr;
        'テスト種別',    'ベースライン (Baseline)';
        '説明',          tcs(i).Description;
    }, '#D6EAF8'));

    % ▼ 紐づく要件
    if ~isempty(reqs)
        add(sec, makeHeading('紐づく要件 (Verified By リンク)'));
        for r = 1:numel(reqs)
            req = reqs{r};
            descTxt = req.Description; if isempty(descTxt), descTxt = '—'; end
            ratTxt  = req.Rationale;   if isempty(ratTxt),  ratTxt  = '—'; end
            add(sec, makeTable2Col({
                '要件 ID',     req.Id;
                'Summary',    req.Summary;
                'Description', descTxt;
                'Rationale',   ratTxt;
            }, '#D5F5E3'));
        end
    end

    % ▼ 波形プロット
    waveFile = fullfile(imgDir, [tcName '_waveform.png']);
    add(sec, makeHeading('入力波形 + 期待出力 (reqDrv)'));
    p_wave = Paragraph('青系: 変化した入力信号のみ表示（全入力 0 の場合は「変化なし」）　赤: 期待出力 reqDrv');
    p_wave.Style = {FontSize('8pt'), OuterMargin('0pt','0pt','2pt','2pt')};
    add(sec, p_wave);
    add(sec, addImg(waveFile, '16cm'));

    % ▼ Model Slicer ハイライト (UseTimeWindow=true + simulate, Test Manager 入力使用)
    add(sec, makeHeading('Model Slicer 動的スライス（TC 固有の実行パスをハイライト）'));
    p_sl = Paragraph(['slsliceroptions.UseTimeWindow=true + slslicer.simulate(simIn) による動的後向きスライス。' ...
        'Test Manager の TestInput (FilePath + InputString) から Dataset を構築し直接 simulate。' ...
        'CoverageFilter は使用しない。' ...
        'Starting point: crs_controller/DriverSwRequest/reqDrv。' ...
        '各 TC の入力に対して実際に実行されたパスのみハイライト。']);
    p_sl.Style = {FontSize('8pt'), OuterMargin('0pt','0pt','4pt','2pt')};
    add(sec, p_sl);

    for k = 1:size(slicerLevels, 1)
        label   = slicerLevels{k,1};
        imgFile = fullfile(imgDir, [tcName '_slicer_' strrep(label,' ','') '.png']);
        add(sec, makeSubheading(['▸ ' slicerLevels{k,2}]));
        add(sec, addImg(imgFile, '15cm'));
    end

    add(ch, sec);
    fprintf('  Section done: %s  [%s]\n', tcName, outcomeStr);
end

add(rpt, ch);
close(rpt);
fprintf('\nReport saved:\n  %s\n', outFile);
rptview(rpt);

%% =========================================================================
%  ローカルヘルパー
%% =========================================================================
function h = makeHeading(txt)
    import mlreportgen.dom.*
    h = Paragraph(txt);
    h.Style = {FontSize('11pt'), Bold, OuterMargin('0pt','0pt','6pt','10pt')};
end

function h = makeSubheading(txt)
    import mlreportgen.dom.*
    h = Paragraph(txt);
    h.Style = {FontSize('9pt'), Bold, OuterMargin('0pt','0pt','3pt','6pt')};
end

function el = addImg(imgFile, width)
    import mlreportgen.dom.*
    if ~isempty(imgFile) && exist(imgFile, 'file')
        el = Image(imgFile);
        el.Style = {Width(width)};
    else
        el = Paragraph('(画像未生成)');
        el.Style = {FontColor('#999999'), FontSize('9pt')};
    end
end

function tbl = makeTable2Col(data, headerBg)
    import mlreportgen.dom.*
    tbl = Table();
    tbl.Style = {Width('100%'), Border('solid','#aaaaaa','0.5pt'), ...
                 ColSep('solid','#cccccc','0.5pt'), RowSep('solid','#cccccc','0.5pt')};
    for i = 1:size(data, 1)
        row = TableRow();
        e1 = TableEntry();
        e1.Style = {BackgroundColor(headerBg), Width('28%'), ...
                    InnerMargin('4pt','4pt','4pt','4pt')};
        p1 = Paragraph(data{i,1}); p1.Style = {Bold, FontSize('9pt')};
        append(e1, p1); append(row, e1);
        e2 = TableEntry();
        e2.Style = {InnerMargin('4pt','4pt','4pt','4pt')};
        p2 = Paragraph(data{i,2}); p2.Style = {FontSize('9pt')};
        append(e2, p2); append(row, e2);
        append(tbl, row);
    end
end
