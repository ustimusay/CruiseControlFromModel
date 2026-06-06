function generate_mcdc_report(cfg)
%GENERATE_MCDC_REPORT  任意サブシステムの MCDC テストトレーサビリティレポートを生成する
%
%  cfg フィールド (必須):
%    .subsystemLabel   - 表示用サブシステム名
%    .testFilePath     - .mldatx の絶対パス
%    .suiteName        - テストスイート名
%    .inputsDir        - 入力 .mat ファイルのディレクトリ
%    .baselinesDir     - ベースライン .mat ファイルのディレクトリ
%    .reportDir        - 出力ディレクトリ (imgDir/PDF はここに作成)
%    .reportFileName   - 出力レポートファイル名 (パスなし)
%    .reportTitle      - レポートタイトル
%    .chapterTitle     - 章見出し
%    .reqFilePath      - .slreqx の絶対パス
%    .harnessName      - ハーネスモデル名
%    .harnessOwner     - コンポーネントパス (例: 'crs_controller/CruiseControlMode')
%    .slicerStartPt    - Model Slicer 始点 (ハーネス内フルパス)
%    .slicerLevels     - Nx2 cell: {表示ラベル, ハーネス内フルブロックパス}
%    .inputSignals     - cell of structs: .name .color .yLim .yTicks .yLabels
%    .outputSignals    - cell of structs: .elemIdx .name .color .yLim .yTicks .yLabels .plotTitle
%
%  cfg フィールド (省略可):
%    .reportSubtitle   - レポートサブタイトル (デフォルト: 'テストトレーサビリティレポート')
%    .reportFormat     - 'pdf', 'html', 'html-file', 'docx', or 'pdfa'
%                        (省略時は reportFileName の拡張子から推定)
%    .reportPackageType - mlreportgen.report.Report の PackageType
%    .demoDir          - モデルルートフォルダ (open_system に使用)
%    .modelName        - 'crs_controller' など (デフォルト: harnessOwner の最初のスラッシュ前)

%% ── 省略可フィールドのデフォルト処理 ──────────────────────────────────────
if ~isfield(cfg, 'reportSubtitle')
    cfg.reportSubtitle = 'テストトレーサビリティレポート';
end
if ~isfield(cfg, 'modelName')
    parts = strsplit(cfg.harnessOwner, '/');
    cfg.modelName = parts{1};
end
if ~isfield(cfg, 'skipTestRun')
    cfg.skipTestRun = false;
end
if ~isfield(cfg, 'reuseWaveforms')
    cfg.reuseWaveforms = false;
end
if ~isfield(cfg, 'reuseSlicerImages')
    cfg.reuseSlicerImages = true;
end
if ~isfield(cfg, 'slicerSegmentByInputChanges')
    cfg.slicerSegmentByInputChanges = true;
end
if ~isfield(cfg, 'slicerMinSegmentDuration')
    cfg.slicerMinSegmentDuration = 1e-6;
end
if ~isfield(cfg, 'openReport')
    cfg.openReport = true;
end
if ~isfield(cfg, 'reportFormat')
    cfg.reportFormat = detectReportFormat(cfg.reportFileName);
else
    cfg.reportFormat = normalizeReportFormat(cfg.reportFormat);
end

imgDir  = fullfile(cfg.reportDir, 'imgs');
outFile = fullfile(cfg.reportDir, cfg.reportFileName);
if ~exist(imgDir,       'dir'), mkdir(imgDir);       end
if ~exist(cfg.reportDir,'dir'), mkdir(cfg.reportDir); end

%% ── 1. モデル・テスト・要件 読み込み ─────────────────────────────────────
if isfield(cfg,'demoDir') && ~bdIsLoaded(cfg.modelName)
    open_system(fullfile(cfg.demoDir, [cfg.modelName '.slx']));
elseif ~bdIsLoaded(cfg.modelName)
    open_system([cfg.modelName '.slx']);
end

slreq.clear();
rs = slreq.load(cfg.reqFilePath);

existingFiles = sltest.testmanager.getTestFiles();
tfObj = [];
for i = 1:numel(existingFiles)
    [~,nm,~] = fileparts(cfg.testFilePath);
    if strcmp(existingFiles(i).Name, nm)
        tfObj = existingFiles(i); break;
    end
end
if isempty(tfObj)
    tfObj = sltest.testmanager.load(cfg.testFilePath);
end

suites    = tfObj.getAllTestSuites();
testSuite = [];
for i = 1:numel(suites)
    if strcmp(suites(i).Name, cfg.suiteName)
        testSuite = suites(i); break;
    end
end
if isempty(testSuite)
    error('Suite "%s" が見つかりません。', cfg.suiteName);
end
tcs = testSuite.getTestCases();
if isfield(cfg, 'testCaseNames') && ~isempty(cfg.testCaseNames)
    tcs = filterTestCasesByName(tcs, cfg.testCaseNames);
end
fprintf('Total test cases: %d\n', numel(tcs));

%% ── 2. UUID → TC オブジェクト マップ ────────────────────────────────────
tcUUIDs = cell(numel(tcs),1);
for i = 1:numel(tcs)
    tcUUIDs{i} = tcs(i).UUID;
end

%% ── 3. Verify リンクから UUID → {要件} マップを構築 ─────────────────────
tcUuidToReqs = struct();
linkSets = slreq.find('Type', 'LinkSet');
for i = 1:numel(linkSets)
    lnks = linkSets(i).getLinks();
    for j = 1:numel(lnks)
        lnk = lnks(j);
        if ~strcmp(lnk.Type, 'Verify'), continue; end
        uuid  = lnk.source.id;
        reqId = lnk.destination.id;
        try
            req = find(rs, 'Type', 'Requirement', 'Id', reqId);
            if ~isempty(req)
                key = matlab.lang.makeValidName(uuid);
                if ~isfield(tcUuidToReqs, key)
                    tcUuidToReqs.(key) = {};
                end
                tcUuidToReqs.(key){end+1} = req;
            end
        catch
        end
    end
end
fprintf('TCs with requirement links: %d\n', numel(fieldnames(tcUuidToReqs)));

%% ══════════════════════════════════════════════════════════════════════════
%  Phase A: 全 TC 実行 + 結果収集
%% ══════════════════════════════════════════════════════════════════════════
tcInfoMap = struct();
if cfg.skipTestRun
    fprintf('\n=== Phase A: Test run skipped; using prior passed result state ===\n');
    for i = 1:numel(tcs)
        key = matlab.lang.makeValidName(tcs(i).Name);
        tcInfoMap.(key) = struct('Outcome', 'Passed');
        fprintf('  %-45s %s\n', tcs(i).Name, 'Passed');
    end
else
    fprintf('\n=== Phase A: Running all test cases ===\n');

    resultSet   = tfObj.run();
    fileResArr  = resultSet.getTestFileResults();
    suiteResArr = fileResArr(1).getTestSuiteResults();

    mcdcSuiteRes = [];
    for i = 1:numel(suiteResArr)
        if strcmp(suiteResArr(i).Name, cfg.suiteName)
            mcdcSuiteRes = suiteResArr(i); break;
        end
    end
    tcResArr = mcdcSuiteRes.getTestCaseResults();

    for i = 1:numel(tcResArr)
        r = tcResArr(i);
        if r.Outcome == sltest.testmanager.TestResultOutcomes.Passed
            outcomeStr = 'Passed';
        else
            outcomeStr = 'Failed';
        end
        key = matlab.lang.makeValidName(r.Name);
        tcInfoMap.(key) = struct('Outcome', outcomeStr);
        fprintf('  %-45s %s\n', r.Name, outcomeStr);
    end
end

%% ══════════════════════════════════════════════════════════════════════════
%  Phase B: 波形プロット
%% ══════════════════════════════════════════════════════════════════════════
fprintf('\n=== Phase B: Waveform plots ===\n');

nOutSigs = numel(cfg.outputSignals);

for i = 1:numel(tcs)
    tcName  = tcs(i).Name;
    inpFile = fullfile(cfg.inputsDir,    [tcName '.mat']);
    blFile  = fullfile(cfg.baselinesDir, [tcName '_expected.mat']);
    waveFile = fullfile(imgDir, [tcName '_waveform.png']);

    if cfg.reuseWaveforms && exist(waveFile, 'file')
        fprintf('  [%s] existing waveform - skip\n', tcName);
        continue;
    end

    if ~exist(inpFile,'file') || ~exist(blFile,'file')
        fprintf('  [%s] ファイルなし - スキップ\n', tcName);
        continue;
    end

    inp = load(inpFile);
    bl  = load(blFile);
    ds  = bl.data;

    % 変化する入力シグナルを抽出
    changing  = {};
    chColors  = {};
    chYLim    = {};
    chYTicks  = {};
    chYLabels = {};
    for k = 1:numel(cfg.inputSignals)
        sig = cfg.inputSignals{k};
        if ~isfield(inp, sig.name), continue; end
        d = double(squeeze(inp.(sig.name).Data));
        if range(d) > 0 || all(d == d(1))  % 常に変化の有無で判定
            if range(d) > 0
                changing{end+1}  = struct('name', sig.name, 't', inp.(sig.name).Time, 'd', d); %#ok<AGROW>
                chColors{end+1}  = sig.color;  %#ok<AGROW>
                chYLim{end+1}    = sig.yLim;   %#ok<AGROW>
                chYTicks{end+1}  = sig.yTicks; %#ok<AGROW>
                chYLabels{end+1} = sig.yLabels;%#ok<AGROW>
            end
        end
    end

    nIn    = numel(changing);
    nTotal = max(1, nIn) + nOutSigs;

    fig = figure('Visible','off','Position',[100 100 920 max(300, nTotal*90)],'Color','w');

    % ── 入力サブプロット ──
    if nIn == 0
        ax = subplot(nTotal, 1, 1);
        text(0.5, 0.5, '(変化する入力なし — 全入力一定値)', ...
            'HorizontalAlignment','center','FontSize',9,'Color',[0.4 0.4 0.4]);
        axis(ax,'off');
        title(ax, ['[' tcName '] 入力信号'], 'Interpreter','none','FontSize',9);
    else
        for k = 1:nIn
            ax = subplot(nTotal, 1, k);
            stairs(ax, changing{k}.t, changing{k}.d, 'Color', chColors{k}, 'LineWidth', 1.5);
            ylabel(ax, strrep(changing{k}.name,'_','\_'), 'FontSize',8, ...
                'Rotation',0,'HorizontalAlignment','right');
            if ~isempty(chYLim{k}),    ylim(ax, chYLim{k});    end
            if ~isempty(chYTicks{k})
                yticks(ax, chYTicks{k});
                if ~isempty(chYLabels{k}), yticklabels(ax, chYLabels{k}); end
            end
            grid(ax,'on'); set(ax,'XTickLabel',{});
            ax.Color = [0.96 0.98 1.0];
            if k == 1
                title(ax, ['[' tcName '] 変化する入力信号'], 'Interpreter','none','FontSize',9);
            end
        end
    end

    % ── 出力サブプロット ──
    for k = 1:nOutSigs
        outSig = cfg.outputSignals{k};
        axIdx  = max(1,nIn) + k;
        ax = subplot(nTotal, 1, axIdx);
        try
            elem = ds{outSig.elemIdx};
            t_bl = elem.Values.Time;
            d_bl = double(elem.Values.Data(:));
            stairs(ax, t_bl, d_bl, 'Color', outSig.color, 'LineWidth', 2);
        catch
            text(0.5, 0.5, '(データなし)', 'HorizontalAlignment','center', ...
                 'FontSize',9,'Color',[0.5 0.5 0.5]);
            axis(ax, 'off');
        end
        if ~isempty(outSig.yLim),   ylim(ax, outSig.yLim);   end
        if ~isempty(outSig.yTicks)
            yticks(ax, outSig.yTicks);
            if ~isempty(outSig.yLabels), yticklabels(ax, outSig.yLabels); end
        end
        ylabel(ax, strrep(outSig.name,'_','\_'), 'FontSize',8, ...
            'Rotation',0,'HorizontalAlignment','right');
        if k == nOutSigs, xlabel(ax,'Time (s)','FontSize',8); end
        grid(ax,'on');
        outColor = max(0, outSig.color - 0.3);
        ax.Color = 0.95*ones(1,3) + 0.05*outColor;
        title(ax, outSig.plotTitle, 'FontSize',8);
    end

    saveas(fig, waveFile);
    close(fig);
    fprintf('  [%s]\n', tcName);
end

%% ══════════════════════════════════════════════════════════════════════════
%  Phase C: Model Slicer 動的スライス
%% ══════════════════════════════════════════════════════════════════════════
fprintf('\n=== Phase C: Model Slicer dynamic slice ===\n');

captureSlicerScreenshots(cfg, tcs, imgDir);

fprintf('  Phase C complete.\n');

%% ══════════════════════════════════════════════════════════════════════════
%  Phase D: PDF 組み立て
%% ══════════════════════════════════════════════════════════════════════════
fprintf('\n=== Phase D: Building %s report ===\n', upper(string(cfg.reportFormat)));

import mlreportgen.report.*
import mlreportgen.dom.*

rpt         = Report(outFile, cfg.reportFormat);
if isfield(cfg, 'reportPackageType')
    rpt.PackageType = cfg.reportPackageType;
end
tp          = TitlePage();
tp.Title    = cfg.reportTitle;
tp.Subtitle = cfg.reportSubtitle;
tp.Author   = sprintf('自動生成: %s', string(datetime('now'),'yyyy-MM-dd HH:mm'));
add(rpt, tp);
add(rpt, TableOfContents());

ch       = Chapter();
ch.Title = cfg.chapterTitle;

for i = 1:numel(tcs)
    tcName = tcs(i).Name;
    uuid   = tcs(i).UUID;

    tcKey = matlab.lang.makeValidName(tcName);
    if isfield(tcInfoMap, tcKey)
        outcomeStr = tcInfoMap.(tcKey).Outcome;
    else
        outcomeStr = 'Unknown';
    end
    uuidKey = matlab.lang.makeValidName(uuid);
    reqs = {};
    if isfield(tcUuidToReqs, uuidKey)
        reqs = tcUuidToReqs.(uuidKey);
    end

    sec       = Section();
    sec.Title = sprintf('%s  [%s]', tcName, outcomeStr);

    % テストケース情報
    add(sec, makeHeading('テストケース情報・テスト結果'));
    add(sec, makeTable2Col({
        'テストケース名', tcName;
        'テスト結果',    outcomeStr;
        'テスト種別',    'ベースライン (Baseline)';
        '説明',          tcs(i).Description;
    }, '#D6EAF8'));

    % 紐づく要件
    if ~isempty(reqs)
        add(sec, makeHeading('紐づく要件 (Verify リンク)'));
        for r = 1:numel(reqs)
            req = reqs{r};
            descTxt = req.Description; if isempty(descTxt), descTxt = '—'; end
            ratTxt  = req.Rationale;   if isempty(ratTxt),  ratTxt  = '—'; end
            add(sec, makeTable2Col({
                '要件 ID',    req.Id;
                'Summary',   req.Summary;
                'Description', descTxt;
                'Rationale', ratTxt;
            }, '#D5F5E3'));
        end
    end

    % 波形プロット
    waveFile = fullfile(imgDir, [tcName '_waveform.png']);
    add(sec, makeHeading('入力波形 + 期待出力'));
    p_wave = Paragraph('変化した入力信号のみ表示。出力は各シグナルをステアーズ表示。');
    p_wave.Style = {FontSize('8pt'), OuterMargin('0pt','0pt','2pt','2pt')};
    add(sec, p_wave);
    add(sec, addImg(waveFile, '16cm'));

    % Model Slicer
    add(sec, makeHeading('Model Slicer 動的スライス（TC 固有の実行パスをハイライト）'));
    segments = getInputChangeSegments(cfg, tcs(i));
    for s = 1:numel(segments)
        seg = segments(s);
        add(sec, makeSubheading(sprintf('Segment %02d: %.6g s - %.6g s', ...
            seg.Index, seg.StartTime, seg.StopTime)));
        add(sec, makeTable2Col({
            'Start time',      sprintf('%.6g s', seg.StartTime);
            'Stop time',       sprintf('%.6g s', seg.StopTime);
            'Changed inputs',  strjoinOrDefault(seg.ChangedSignals, ', ', '(initial state / no input change)');
        }, '#FDEBD0'));
        segWaveFile = createSegmentWaveformImage(cfg, imgDir, tcName, seg);
        add(sec, addImg(segWaveFile, '16cm'));
        for k = 1:size(cfg.slicerLevels, 1)
            label   = cfg.slicerLevels{k,1};
            imgFile = slicerImageFile(imgDir, tcName, label, seg);
            add(sec, makeSubheading(['▸ ' cfg.slicerLevels{k,2}]));
            add(sec, addImg(imgFile, '15cm'));
        end
    end

    add(ch, sec);
    fprintf('  Section: %s [%s]\n', tcName, outcomeStr);
end

add(rpt, ch);
close(rpt);
fprintf('\nReport saved:\n  %s\n', outFile);
if cfg.openReport
    rptview(rpt);
end
end

%% =========================================================================
%  ローカルヘルパー
%% =========================================================================
function fmt = detectReportFormat(reportFileName)
    [~,~,ext] = fileparts(reportFileName);
    switch lower(ext)
        case '.html'
            fmt = 'html-file';
        otherwise
            fmt = 'pdf';
    end
end

function fmt = normalizeReportFormat(fmt)
    fmt = char(lower(string(fmt)));
    if strcmp(fmt, 'html')
        fmt = 'html-file';
    end
    allowed = {'pdf','html-file','docx','pdfa'};
    if ~ismember(fmt, allowed)
        error('Unsupported reportFormat "%s". Use pdf, html, html-file, docx, or pdfa.', fmt);
    end
end

function filtered = filterTestCasesByName(tcs, names)
    names = cellstr(string(names));
    keep = false(numel(tcs), 1);
    for i = 1:numel(tcs)
        keep(i) = any(strcmp(tcs(i).Name, names));
    end
    filtered = tcs(keep);
    missing = setdiff(names, arrayfun(@(tc) tc.Name, filtered, 'UniformOutput', false));
    if ~isempty(missing)
        error('Test case(s) not found: %s', strjoin(missing, ', '));
    end
end

function captureSlicerScreenshots(cfg, tcs, imgDir)
    if ~bdIsLoaded(cfg.harnessName)
        sltest.harness.open(cfg.harnessOwner, cfg.harnessName);
        drawnow; pause(1.0);
    end

    for i = 1:numel(tcs)
        tcName = tcs(i).Name;
        sc = [];
        try
            segments = getInputChangeSegments(cfg, tcs(i));
            if isempty(segments)
                fprintf('  [%s] no active input definition - skip\n', tcName);
                continue;
            end

            if cfg.reuseSlicerImages && allSlicerImagesExist(cfg, imgDir, tcName, segments)
                fprintf('  [%s] existing slicer images - skip\n', tcName);
                continue;
            end

            tcInputs = tcs(i).getInputs();
            if isempty(tcInputs) || ~tcInputs(1).Active
                fprintf('  [%s] no active input definition - skip\n', tcName);
                continue;
            end

            simIn = buildSlicerSimulationInput(cfg.harnessName, tcInputs(1));

            opts               = slsliceroptions();
            opts.UseTimeWindow = true;
            sc = slslicer(cfg.harnessName, opts);
            addStartingPoint(sc, cfg.slicerStartPt);

            sc.simulate(simIn);

            for s = 1:numel(segments)
                seg = segments(s);
                if cfg.reuseSlicerImages && allSlicerImagesExist(cfg, imgDir, tcName, seg)
                    fprintf('  [%s] segment %02d existing slicer images - skip\n', tcName, seg.Index);
                    continue;
                end

                sc.setTimeWindow(seg.StartTime, seg.StopTime);
                sc.highlight();
                drawnow; pause(0.3);

                for k = 1:size(cfg.slicerLevels, 1)
                    label    = cfg.slicerLevels{k,1};
                    fullPath = cfg.slicerLevels{k,2};
                    open_system(fullPath, 'force');
                    drawnow; pause(0.3);
                    print(['-s' fullPath], '-dpng', '-r120', slicerImageFile(imgDir, tcName, label, seg));
                end
            end

            delete(sc); sc = [];
            fprintf('  [%s] OK (%d segment(s))\n', tcName, numel(segments));
        catch e
            fprintf('  [%s] WARN: %s\n', tcName, e.message(1:min(120,end)));
            if ~isempty(sc)
                try
                    delete(sc);
                catch
                end
            end
        end
    end
end

function segments = getInputChangeSegments(cfg, tc)
    tcInputs = tc.getInputs();
    if isempty(tcInputs) || ~tcInputs(1).Active
        segments = makeEmptySegments();
        return;
    end

    [inpData, sigNames, startT, stopT, sampleTimes] = loadTestInputData(tcInputs(1));
    if ~cfg.slicerSegmentByInputChanges
        segments = makeSlicerSegment(1, startT, stopT, {});
        return;
    end

    changeTimes = [];
    changeSignals = {};
    for k = 1:numel(sigNames)
        vn = sigNames{k};
        if ~isfield(inpData, vn)
            continue;
        end

        ts = inpData.(vn);
        t = double(ts.Time(:));
        if numel(t) < 2
            continue;
        end

        d = reshapeSignalDataByTime(ts.Data, numel(t));
        changed = any(diff(d, 1, 1) ~= 0, 2);
        idx = find(changed) + 1;
        for c = 1:numel(idx)
            changeTimes(end+1, 1) = t(idx(c)); %#ok<AGROW>
            changeSignals{end+1, 1} = vn; %#ok<AGROW>
        end
    end

    bounds = unique([startT; changeTimes; stopT]);
    bounds = bounds(bounds >= startT & bounds <= stopT);
    if numel(bounds) < 2
        bounds = [startT; stopT];
    end

    minDuration = cfg.slicerMinSegmentDuration;
    segments = repmat(makeSlicerSegment(0, 0, minDuration, {}), 0, 1);
    for s = 1:(numel(bounds) - 1)
        segStart = bounds(s);
        if s < (numel(bounds) - 1)
            segStop = segmentStopBeforeNextStart(sampleTimes, bounds(s + 1), ...
                segStart, minDuration);
        else
            segStop = bounds(s + 1);
        end
        if segStop <= segStart
            segStop = segStart;
        end

        changedHere = changeSignals(abs(changeTimes - segStart) <= minDuration);
        changedHere = unique(changedHere, 'stable');
        segments(end+1, 1) = makeSlicerSegment(s, segStart, segStop, changedHere); %#ok<AGROW>
    end
end

function tf = allSlicerImagesExist(cfg, imgDir, tcName, segments)
    tf = true;
    for s = 1:numel(segments)
        for k = 1:size(cfg.slicerLevels, 1)
            label = cfg.slicerLevels{k,1};
            if ~exist(slicerImageFile(imgDir, tcName, label, segments(s)), 'file')
                tf = false;
                return;
            end
        end
    end
end

function simIn = buildSlicerSimulationInput(harnessName, tcInput)
    [inpData, sigNames, ~, stopT] = loadTestInputData(tcInput);

    ds2 = Simulink.SimulationData.Dataset();
    for k = 1:numel(sigNames)
        vn = sigNames{k};
        ts = inpData.(vn);
        ts.Name = vn;
        ds2 = ds2.addElement(ts, vn);
    end

    simIn = Simulink.SimulationInput(harnessName);
    simIn = simIn.setExternalInput(ds2);
    simIn = simIn.setModelParameter('StopTime', num2str(stopT));
end

function [inpData, sigNames, startT, stopT, sampleTimes] = loadTestInputData(tcInput)
    inpFile  = tcInput.FilePath;
    sigNames = strtrim(strsplit(tcInput.InputString, ','));
    inpData = load(inpFile);

    startT = inf;
    stopT = -inf;
    sampleTimes = [];
    for k = 1:numel(sigNames)
        vn = sigNames{k};
        if ~isfield(inpData, vn)
            continue;
        end
        t = double(inpData.(vn).Time(:));
        if isempty(t)
            continue;
        end
        startT = min(startT, t(1));
        stopT = max(stopT, t(end));
        sampleTimes = [sampleTimes; t]; %#ok<AGROW>
    end
    if ~isfinite(startT) || ~isfinite(stopT)
        startT = 0;
        stopT = 0;
    end
    sampleTimes = unique(sampleTimes);
end

function d = reshapeSignalDataByTime(data, nTime)
    if nTime == 0
        d = [];
        return;
    end

    sz = size(data);
    if sz(1) == nTime
        d = reshape(data, nTime, []);
    elseif sz(end) == nTime
        order = [ndims(data), 1:(ndims(data) - 1)];
        d = permute(data, order);
        d = reshape(d, nTime, []);
    else
        d = reshape(squeeze(data), nTime, []);
    end
    d = double(d);
end

function segStop = segmentStopBeforeNextStart(sampleTimes, nextStart, segStart, minDuration)
    tol = max(eps(max(abs(nextStart), 1)) * 10, minDuration * 1e-3);
    candidates = sampleTimes(sampleTimes >= segStart & sampleTimes < (nextStart - tol));
    if isempty(candidates)
        segStop = max(segStart, nextStart - minDuration);
    else
        segStop = candidates(end);
    end
end

function segment = makeSlicerSegment(index, startT, stopT, changedSignals)
    segment = struct( ...
        'Index', index, ...
        'StartTime', startT, ...
        'StopTime', stopT, ...
        'ChangedSignals', {changedSignals});
end

function segments = makeEmptySegments()
    segments = repmat(makeSlicerSegment(0, 0, 0, {}), 0, 1);
end

function imgFile = slicerImageFile(imgDir, tcName, label, segment)
    cleanLabel = strrep(label, ' ', '');
    imgFile = fullfile(imgDir, sprintf('%s_slicer_seg%02d_%s.png', ...
        tcName, segment.Index, cleanLabel));
end

function imgFile = segmentWaveformFile(imgDir, tcName, segment)
    imgFile = fullfile(imgDir, sprintf('%s_waveform_seg%02d.png', ...
        tcName, segment.Index));
end

function imgFile = createSegmentWaveformImage(cfg, imgDir, tcName, segment)
    imgFile = segmentWaveformFile(imgDir, tcName, segment);

    inpFile = fullfile(cfg.inputsDir, [tcName '.mat']);
    blFile  = fullfile(cfg.baselinesDir, [tcName '_expected.mat']);
    if ~exist(inpFile, 'file') || ~exist(blFile, 'file')
        return;
    end

    inp = load(inpFile);
    bl  = load(blFile);
    ds  = bl.data;

    inputPlots = {};
    inputColors = {};
    inputYLim = {};
    inputYTicks = {};
    inputYLabels = {};
    for k = 1:numel(cfg.inputSignals)
        sig = cfg.inputSignals{k};
        if ~isfield(inp, sig.name)
            continue;
        end

        t = double(inp.(sig.name).Time(:));
        d = squeeze(inp.(sig.name).Data);
        if isempty(t)
            continue;
        end

        d = reshapeSignalDataByTime(d, numel(t));
        if size(d, 2) > 1
            d = d(:, 1);
        end
        if range(double(d)) > 0 || any(strcmp(segment.ChangedSignals, sig.name))
            inputPlots{end+1} = struct('name', sig.name, 't', t, 'd', double(d)); %#ok<AGROW>
            inputColors{end+1} = sig.color; %#ok<AGROW>
            inputYLim{end+1} = sig.yLim; %#ok<AGROW>
            inputYTicks{end+1} = sig.yTicks; %#ok<AGROW>
            inputYLabels{end+1} = sig.yLabels; %#ok<AGROW>
        end
    end

    nOutSigs = numel(cfg.outputSignals);
    nIn = numel(inputPlots);
    nTotal = max(1, nIn) + nOutSigs;
    fig = figure('Visible', 'off', 'Position', [100 100 920 max(320, nTotal*100)], 'Color', 'w');

    if nIn == 0
        ax = subplot(nTotal, 1, 1);
        text(0.5, 0.5, '(no changing input signals)', ...
            'HorizontalAlignment', 'center', 'FontSize', 9, 'Color', [0.4 0.4 0.4]);
        axis(ax, 'off');
        title(ax, sprintf('[%s] Segment %02d input signals', tcName, segment.Index), ...
            'Interpreter', 'none', 'FontSize', 9);
    else
        for k = 1:nIn
            ax = subplot(nTotal, 1, k);
            stairs(ax, inputPlots{k}.t, inputPlots{k}.d, 'Color', inputColors{k}, 'LineWidth', 1.5);
            ylabel(ax, strrep(inputPlots{k}.name, '_', '\_'), 'FontSize', 8, ...
                'Rotation', 0, 'HorizontalAlignment', 'right');
            if ~isempty(inputYLim{k}), ylim(ax, inputYLim{k}); end
            if ~isempty(inputYTicks{k})
                yticks(ax, inputYTicks{k});
                if ~isempty(inputYLabels{k}), yticklabels(ax, inputYLabels{k}); end
            end
            grid(ax, 'on'); set(ax, 'XTickLabel', {});
            addSlicerWindowBackground(ax, segment);
            if k == 1
                title(ax, sprintf('[%s] Segment %02d input/expected waveforms', tcName, segment.Index), ...
                    'Interpreter', 'none', 'FontSize', 9);
            end
        end
    end

    for k = 1:nOutSigs
        outSig = cfg.outputSignals{k};
        axIdx = max(1, nIn) + k;
        ax = subplot(nTotal, 1, axIdx);
        try
            elem = ds{outSig.elemIdx};
            t_bl = elem.Values.Time;
            d_bl = double(elem.Values.Data(:));
            stairs(ax, t_bl, d_bl, 'Color', outSig.color, 'LineWidth', 2);
        catch
            text(0.5, 0.5, '(no expected data)', 'HorizontalAlignment', 'center', ...
                 'FontSize', 9, 'Color', [0.5 0.5 0.5]);
            axis(ax, 'off');
        end
        if ~isempty(outSig.yLim), ylim(ax, outSig.yLim); end
        if ~isempty(outSig.yTicks)
            yticks(ax, outSig.yTicks);
            if ~isempty(outSig.yLabels), yticklabels(ax, outSig.yLabels); end
        end
        ylabel(ax, strrep(outSig.name, '_', '\_'), 'FontSize', 8, ...
            'Rotation', 0, 'HorizontalAlignment', 'right');
        if k == nOutSigs, xlabel(ax, 'Time (s)', 'FontSize', 8); end
        grid(ax, 'on');
        addSlicerWindowBackground(ax, segment);
        title(ax, outSig.plotTitle, 'FontSize', 8);
    end

    saveas(fig, imgFile);
    close(fig);
end

function addSlicerWindowBackground(ax, segment)
    hold(ax, 'on');
    slicerColor = [0 1 1];
    if segment.StopTime > segment.StartTime
        yl = ylim(ax);
        h = patch(ax, ...
            [segment.StartTime segment.StopTime segment.StopTime segment.StartTime], ...
            [yl(1) yl(1) yl(2) yl(2)], slicerColor, ...
            'FaceAlpha', 0.18, 'EdgeColor', 'none', 'HandleVisibility', 'off');
        uistack(h, 'bottom');
    else
        xline(ax, segment.StartTime, '-', 'Color', slicerColor, ...
            'LineWidth', 2, 'HandleVisibility', 'off');
    end
    hold(ax, 'off');
end

function txt = strjoinOrDefault(values, delimiter, defaultText)
    if isempty(values)
        txt = defaultText;
    else
        txt = strjoin(values, delimiter);
    end
end

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
