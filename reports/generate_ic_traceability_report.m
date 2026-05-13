%% generate_ic_traceability_report.m  (v4)
%  Input_Conditioning テストトレーサビリティレポートを PDF で生成する
%
%  各 TC セクション:
%    1. テストケース情報・要求テーブル
%    2. 子サブシステム内部スクリーンショット
%    3. 入力 / 出力 波形プロット
%    4. Model Slicer ハイライト
%       ・slicer は crs_controller (main model) 上で実行
%       ・子サブシステムブロックを starting point として静的依存解析
%       ・IC 親レベルのスクリーンショット → どの child が対象かを強調表示
%
%  フェーズ分離でシミュレーション競合を回避:
%    Phase A: 全 TC 分の子サブシステム内部スクリーンショット (sim 不要)
%    Phase B: 全 TC 分の波形プロット (harness sim × 6)
%    Phase C: 全 TC 分の Model Slicer ハイライト (crs_controller で静的解析)
%    Phase D: PDF 組み立て

projDir = 'C:\work\demos\CruiseControl';
imgDir  = fullfile(projDir, 'reports', 'imgs');
outFile = fullfile(projDir, 'reports', 'IC_traceability_report.pdf');
if ~exist(imgDir, 'dir'), mkdir(imgDir); end

%% ── 1. アーティファクト読み込み ──────────────────────────────────────────
if ~bdIsLoaded('crs_controller'), open_system('crs_controller'); end
rs = slreq.load(fullfile(projDir, 'crs_controller_requirements.slreqx'));

tmPath = fullfile(projDir, 'crs_controller_tests.mldatx');
existingFiles = sltest.testmanager.getTestFiles();
tfObj = [];
for i = 1:numel(existingFiles)
    if strcmp(existingFiles(i).Name, 'crs_controller_tests')
        tfObj = existingFiles(i); break;
    end
end
if isempty(tfObj), tfObj = sltest.testmanager.load(tmPath); end

%% ── 2. リンクマップ・UUID→TC マップ ──────────────────────────────────────
verifyMap    = containers.Map();
implementMap = containers.Map();
linkSets = slreq.find('Type', 'LinkSet');
for i = 1:numel(linkSets)
    lnks = linkSets(i).getLinks();
    for j = 1:numel(lnks)
        lnk = lnks(j);
        if strcmp(lnk.Type, 'Verify'),    verifyMap(lnk.destination.id)    = lnk.source.id; end
        if strcmp(lnk.Type, 'Implement'), implementMap(lnk.destination.id) = lnk.source.id; end
    end
end

tcMap  = containers.Map();
suites = tfObj.getTestSuites();
for s = 1:numel(suites)
    tcs = suites(s).getTestCases();
    for t = 1:numel(tcs)
        tcMap(tcs(t).UUID) = tcs(t);
    end
end

%% ── 3. IC 定義テーブル ───────────────────────────────────────────────────
%  reqId | child subsystem name
icDefs = {
    'IC-001', 'Button_Rise_Detection';
    'IC-002', 'Button_Hold_Detection';
    'IC-003', 'Brake_Detection';
    'IC-004', 'Key_Decode';
    'IC-005', 'Gear_Decode';
    'IC-006', 'Speed_Range_Check';
};

hName    = 'Input_Conditioning_Harness';
seBlk    = [hName '/Harness Inputs'];
matFile  = fullfile(projDir, 'Input_Conditioning_Harness_HarnessInputs.mat');
icParent = 'crs_controller/Input_Conditioning';

%% ── 4. 要求リンクから Outport パスマップを構築 ──────────────────────────────
%  slreq の Implement リンクをたどり reqId → {Outport ブロックフルパス} を取得
fprintf('Building Outport map from requirement links...\n');
outPortMap = containers.Map();
for k = 1:size(icDefs, 1)
    reqId = icDefs{k,1};
    req   = find(rs, 'Type', 'Requirement', 'Id', reqId);
    paths = {};
    for ls = 1:numel(linkSets)
        lnks = linkSets(ls).getLinks();
        for j = 1:numel(lnks)
            lnk = lnks(j);
            if strcmp(lnk.Type, 'Implement') && strcmp(lnk.destination.id, req.Id)
                try
                    sid   = strrep(lnk.source.id, ':', '');
                    h     = Simulink.ID.getHandle(['crs_controller:' sid]);
                    bpath = getfullname(h);
                    if strcmp(get_param(bpath, 'BlockType'), 'Outport') && ...
                       startsWith(bpath, icParent)
                        paths{end+1} = bpath; %#ok<AGROW>
                    end
                catch
                end
            end
        end
    end
    outPortMap(reqId) = paths;
    pnames = cellfun(@(p) p(length(icParent)+2:end), paths, 'UniformOutput', false);
    fprintf('  [%s] Outports: %s\n', reqId, strjoin(pnames, ', '));
end

%% ═══════════════════════════════════════════════════════════════════════════
%  Phase A: 子サブシステム内部スクリーンショット (sim 不要)
%% ═══════════════════════════════════════════════════════════════════════════
fprintf('=== Phase A: Subsystem screenshots ===\n');
for k = 1:size(icDefs, 1)
    reqId   = icDefs{k,1};
    blkName = icDefs{k,2};
    blkPath = [icParent '/' blkName];
    ssFile  = fullfile(imgDir, [reqId '_subsys.png']);

    open_system(blkPath, 'force');
    drawnow; pause(0.5);
    print(['-scrs_controller'], '-dpng', '-r96', ssFile);
    fprintf('  [%s] %s\n', reqId, blkName);
end

%% ═══════════════════════════════════════════════════════════════════════════
%  Phase B: 波形プロット (harness sim × 6)
%% ═══════════════════════════════════════════════════════════════════════════
fprintf('\n=== Phase B: Waveform plots ===\n');

% data dictionary と競合する base workspace 変数をクリア
evalin('base', 'clear status key gear enbl cncl inc dec resume vehicle_speed brakeP');

% ハーネスをクリーンな状態で確保
reopenHarness('crs_controller/Input_Conditioning', hName);

for k = 1:size(icDefs, 1)
    reqId    = icDefs{k,1};
    iters    = tcMap(verifyMap(reqId)).getIterations();
    scenario = iters(1).Name;
    waveFile = fullfile(imgDir, [reqId '_waveform.png']);

    % 前回 sim の残留状態をクリア
    ensureStopped(hName);

    set_param(seBlk, 'ActiveScenario', scenario);
    simOut = sim(hName, 'StopTime', '10');
    captureWaveform(scenario, matFile, simOut, waveFile, reqId);
    fprintf('  [%s] scenario=%s\n', reqId, scenario);
end
ensureStopped(hName);
try, bdclose(hName); catch, end   % Phase C は harness 不要なので閉じる

%% ═══════════════════════════════════════════════════════════════════════════
%  Phase C: Model Slicer ハイライト (動的スライス — シミュレーション実行)
%    ループ毎に sc を terminate → 再生成して starting point をリセット
%% ═══════════════════════════════════════════════════════════════════════════
fprintf('\n=== Phase C: Model Slicer highlights (dynamic) ===\n');

open_system(icParent, 'force');
drawnow; pause(0.5);

for k = 1:size(icDefs, 1)
    reqId        = icDefs{k,1};
    blkName      = icDefs{k,2};
    outPortPaths = outPortMap(reqId);   % Outport フルパス (slreq リンクから取得)
    slicerFile      = fullfile(imgDir, [reqId '_slicer.png']);
    slicerChildFile = fullfile(imgDir, [reqId '_slicer_child.png']);

    sc = [];
    try
        % ── Starting point リセット: terminate + 再生成 ──────────────────
        sc = slslicer('crs_controller');

        % Starting point を明示的にリセット (StartingPoint は struct 配列)
        existingSP = sc.StartingPoint;
        fprintf('  [%s] existing SPs before reset: %d\n', reqId, numel(existingSP));
        for m = 1:numel(existingSP)
            try
                sc.removeStartingPoint(existingSP(m).Path);
            catch re
                fprintf('    removeStartingPoint warn: %s\n', re.message);
            end
        end

        % 要求にリンクされた Outport ブロックを starting point に設定
        for m = 1:numel(outPortPaths)
            sc.addStartingPoint(outPortPaths{m});
        end
        fprintf('  [%s] SPs after add: %d\n', reqId, numel(sc.StartingPoint));

        % ── 動的スライス: シミュレーション実行 ──────────────────────────
        sc.simulate();

        % シミュレーション完了を待機 (最大 30 秒)
        for w = 1:60
            try
                if strcmp(get_param('crs_controller', 'SimulationStatus'), 'stopped')
                    break;
                end
            catch
                break;
            end
            pause(0.5);
        end
        % 念のため停止を確実に
        try
            if ~strcmp(get_param('crs_controller', 'SimulationStatus'), 'stopped')
                set_param('crs_controller', 'SimulationCommand', 'stop');
                pause(1);
            end
        catch, end
        drawnow; pause(0.8);

        % ── 1枚目: crs_controller ルートレベル ──────────────────────────
        open_system('crs_controller');
        drawnow; pause(0.8);
        print('-scrs_controller', '-dpng', '-r96', slicerFile);

        % ── 2枚目: Input_Conditioning 内部 ───────────────────────────────
        open_system(icParent, 'force');
        drawnow; pause(1.0);
        print(['-s' icParent], '-dpng', '-r96', slicerChildFile);

        sc.terminate();
        drawnow; pause(0.5);
        fprintf('  [%s] slicer OK (dynamic)\n', reqId);
    catch e
        fprintf('  [%s] slicer WARN: %s\n', reqId, e.message);
        if ~isempty(sc)
            try, sc.terminate(); catch, end
        end
        % モデルが停止していない場合は強制停止
        try
            if ~strcmp(get_param('crs_controller', 'SimulationStatus'), 'stopped')
                set_param('crs_controller', 'SimulationCommand', 'stop');
                pause(1);
            end
        catch, end
        slicerFile      = '';
        slicerChildFile = '';
    end
    icDefs{k,3} = slicerFile;        % IC 親レベル画像パス
    icDefs{k,4} = slicerChildFile;   % 子サブシステム内部画像パス
end

%% ═══════════════════════════════════════════════════════════════════════════
%  Phase D: PDF 組み立て
%% ═══════════════════════════════════════════════════════════════════════════
fprintf('\n=== Phase D: Building PDF report ===\n');
import mlreportgen.report.*
import mlreportgen.dom.*

rpt = Report(outFile, 'pdf');

tp          = TitlePage();
tp.Title    = 'CruiseControl';
tp.Subtitle = 'テストトレーサビリティレポート — Input_Conditioning';
tp.Author   = sprintf('自動生成: %s', string(datetime('now'), 'yyyy-MM-dd'));
add(rpt, tp);
add(rpt, TableOfContents());

ch       = Chapter();
ch.Title = 'Input_Conditioning テストケース（IC-001 〜 IC-006）';

for k = 1:size(icDefs, 1)
    reqId   = icDefs{k,1};
    blkName = icDefs{k,2};

    req      = find(rs, 'Type', 'Requirement', 'Id', reqId);
    tc       = tcMap(verifyMap(reqId));
    iters_d  = tc.getIterations();
    scenario = iters_d(1).Name;
    blkPath  = [icParent '/' blkName];   % 子サブシステムのフルパス

    descText = req.Description;
    if isempty(descText), descText = '—'; end

    ssFile          = fullfile(imgDir, [reqId '_subsys.png']);
    waveFile        = fullfile(imgDir, [reqId '_waveform.png']);
    slicerFile      = icDefs{k,3};
    slicerChildFile = icDefs{k,4};

    % ── Section ──
    sec       = Section();
    sec.Title = [reqId ' : ' tc.Name];

    % ▼ テストケース情報
    add(sec, makeHeading('テストケース情報'));
    add(sec, makeTable2Col({
        'テストケース名', tc.Name;
        'スイート',       tc.Parent.Name;
        'シナリオ',       scenario;
    }, '#D6EAF8'));

    % ▼ 紐づく要求
    add(sec, makeHeading('紐づく要求'));
    add(sec, makeTable2Col({
        '要求 ID',      req.Id;
        'Summary',     req.Summary;
        'Description', descText;
        '実装ブロック', blkPath;
    }, '#D5F5E3'));

    % ▼ 実装モデル (子サブシステム内部)
    add(sec, makeHeading(['実装モデル内部: ' blkName]));
    add(sec, addImg(ssFile, '16cm'));

    % ▼ 波形
    add(sec, makeHeading(['シミュレーション波形  (シナリオ: ' scenario ')']));
    p = Paragraph('青: 入力シグナル (変化したもののみ)　　赤: 出力シグナル (変化したもののみ)');
    p.Style = {FontSize('8pt'), OuterMargin('0pt','0pt','0pt','2pt')};
    add(sec, p);
    add(sec, addImg(waveFile, '16cm'));

    % ▼ Model Slicer ハイライト (1/2) — crs_controller ルートレベル
    opaths  = outPortMap(reqId);
    pnames  = cellfun(@(p) p(length(icParent)+2:end), opaths, 'UniformOutput', false);
    spNote  = strjoin(pnames, ', ');
    add(sec, makeHeading(['Model Slicer (1/2): crs_controller ルートレベル — starting point: ' spNote]));
    p2 = Paragraph('5 サブシステムのうち Input_Conditioning (および依存ブロック) がハイライト');
    p2.Style = {FontSize('8pt'), OuterMargin('0pt','0pt','0pt','2pt')};
    add(sec, p2);
    add(sec, addImg(slicerFile, '16cm'));

    % ▼ Model Slicer ハイライト (2/2) — Input_Conditioning 内部（子サブシステム一覧）
    add(sec, makeHeading(['Model Slicer (2/2): Input_Conditioning 内部 — ' blkName ' がハイライト']));
    p3 = Paragraph('6 子サブシステムのうち対象ブロック (および依存ブロック) がハイライト');
    p3.Style = {FontSize('8pt'), OuterMargin('0pt','0pt','0pt','2pt')};
    add(sec, p3);
    add(sec, addImg(slicerChildFile, '16cm'));

    add(ch, sec);
    fprintf('  Section done: %s\n', tc.Name);
end

add(rpt, ch);
close(rpt);
fprintf('\nReport saved: %s\n', outFile);
rptview(rpt);

%% =========================================================================
%  ローカルヘルパー
%% =========================================================================
function reopenHarness(icPath, harnessName)
    % paused/running 状態でも安全に閉じて再オープンする
    if bdIsLoaded(harnessName)
        try, bdclose(harnessName); catch, end
    end
    sltest.harness.open(icPath, harnessName);
    drawnow; pause(1);
    try, set_param(harnessName, 'FastRestart', 'off'); catch, end
end

function ensureStopped(modelName)
    try
        status = get_param(modelName, 'SimulationStatus');
        if ~strcmp(status, 'stopped')
            set_param(modelName, 'SimulationCommand', 'stop');
            pause(0.5);
        end
    catch, end
end

function captureWaveform(scenario, matFile, simOut, waveFile, reqId)
    S  = load(matFile);
    ds = S.(scenario);

    % 変化する入力を抽出
    inSigs = {};
    for i = 1:ds.numElements
        ts = ds{i};
        if range(double(ts.Data(:))) > 0
            inSigs{end+1} = ts; %#ok<AGROW>
        end
    end

    % 変化する出力を抽出
    outSigs = {};
    for i = 1:simOut.yout.numElements
        el = simOut.yout{i};
        if range(double(el.Values.Data(:))) > 0
            outSigs{end+1} = el; %#ok<AGROW>
        end
    end

    nIn = numel(inSigs); nOut = numel(outSigs);
    if nIn + nOut == 0
        fig = figure('Visible','off','Position',[100 100 900 200]);
        text(0.5,0.5,'(変化するシグナルなし)','HorizontalAlignment','center');
        axis off; saveas(fig, waveFile); close(fig); return;
    end

    nTotal = nIn + nOut;
    fig = figure('Visible','off','Position',[100 100 900 max(300, nTotal*90)]);

    for i = 1:nIn
        ax = subplot(nTotal, 1, i);
        ts = inSigs{i};
        stairs(ts.Time, double(ts.Data(:)), 'Color', [0.1 0.4 0.8], 'LineWidth', 1.2);
        ylabel(ts.Name, 'Interpreter','none','FontSize',8);
        grid on; ax.XTickLabel = {};
        ax.Color = [0.94 0.97 1.0];
        if i == 1
            title(sprintf('[%s]  Scenario: %s', reqId, scenario), ...
                'Interpreter','none','FontSize',9);
        end
    end

    for i = 1:nOut
        ax = subplot(nTotal, 1, nIn+i);
        el = outSigs{i};
        stairs(el.Values.Time, double(el.Values.Data(:)), ...
               'Color', [0.8 0.2 0.1], 'LineWidth', 1.2);
        ylabel(el.Name, 'Interpreter','none','FontSize',8);
        grid on;
        if i < nOut, ax.XTickLabel = {}; end
        ax.Color = [1.0 0.96 0.94];
    end
    xlabel('Time (s)');

    saveas(fig, waveFile);
    close(fig);
end

function h = makeHeading(txt)
    import mlreportgen.dom.*
    h = Paragraph(txt);
    h.Style = {FontSize('11pt'), Bold, OuterMargin('0pt','0pt','8pt','3pt')};
end

function el = addImg(imgFile, width)
    import mlreportgen.dom.*
    if ~isempty(imgFile) && exist(imgFile, 'file')
        el = Image(imgFile);
        el.Style = {Width(width)};
    else
        el = Paragraph('(画像未生成)');
    end
end

function tbl = makeTable2Col(data, headerBg)
    import mlreportgen.dom.*
    tbl = Table();
    tbl.Style = {Width('100%'), Border('solid','#888888','1pt'), ...
                 ColSep('solid','#CCCCCC','1pt'), RowSep('solid','#CCCCCC','1pt')};
    for i = 1:size(data,1)
        row = TableRow();
        e1 = TableEntry();
        e1.Style = {BackgroundColor(headerBg), Width('30%'), ...
                    InnerMargin('4pt','4pt','4pt','4pt')};
        p1 = Paragraph(data{i,1}); p1.Style = {Bold};
        append(e1, p1); append(row, e1);
        e2 = TableEntry();
        e2.Style = {InnerMargin('4pt','4pt','4pt','4pt')};
        append(e2, Paragraph(data{i,2}));
        append(row, e2);
        append(tbl, row);
    end
end
