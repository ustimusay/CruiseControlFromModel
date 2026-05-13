%% add_DriverSwRequest_BlockRequirements.m
% DriverSwRequest 内の Switch/Constant/Delay/LogicalOperator/RelationalOperator
% ブロックに対応する要件を crs_controller_requirements.slreqx に追加し、
% Implement リンクを作成する。

rootDir = currentProject().RootFolder;
slreq.clear();

if ~bdIsLoaded('crs_controller')
    open_system(fullfile(rootDir, 'crs_controller.slx'));
    drawnow; pause(1);
end

rs   = slreq.load(fullfile(rootDir, 'crs_controller_requirements.slreqx'));

req1 = find(rs, 'Type', 'Requirement', 'Id', '#1');  % DriverSwRequest
req4 = find(rs, 'Type', 'Requirement', 'Id', '#4');  % decrement
req5 = find(rs, 'Type', 'Requirement', 'Id', '#5');  % increment
req6 = find(rs, 'Type', 'Requirement', 'Id', '#6');  % doNot Repeat
req7 = find(rs, 'Type', 'Requirement', 'Id', '#7');  % counter (decrement)
req8 = find(rs, 'Type', 'Requirement', 'Id', '#8');  % counter (increment)

dsrPath = 'crs_controller/DriverSwRequest';
decPath = [dsrPath '/decrement'];
incPath = [dsrPath '/increment'];
dnrPath = [dsrPath '/doNot Repeat'];

%% ════════════════════════════════════════════════════════════════════════
%%  新規要件の追加
%% ════════════════════════════════════════════════════════════════════════

%% ── #1 DriverSwRequest 直下 ─────────────────────────────────────────────

rConst1 = add(req1);
rConst1.Summary     = '優先度選択定数の定義';
rConst1.Description = ['cncl/enbl/set/resume の各スイッチ操作と無入力に対応する ' ...
    'reqMode 列挙値（Cancel / Cruise / Set / ResumeReq / NoRequest）を ' ...
    'EnumeratedConstant ブロックとして定義する。' ...
    'これらの値が優先度付き Switch チェーンの入力定数となる。'];

rSwPri = add(req1);
rSwPri.Summary     = '優先度付きスイッチ選択チェーン';
rSwPri.Description = ['cncl > enbl > set > resume の優先度順に Switch ブロックを直列に接続し、' ...
    '有効な入力のうち最高優先度の reqMode を選択する。' ...
    'いずれの入力も false のときは dec/inc サブシステムの出力をパススルーする。'];

rDelay1 = add(req1);
rDelay1.Summary     = '前サンプル要求の保持（DriverSwRequest）';
rDelay1.Description = ['1 サンプル前の reqDrv を Delay で保持する。' ...
    'この値を doNot Repeat サブシステムおよび dec/inc サブシステムの ' ...
    'prev_req（前サンプル要求）として供給する。'];

%% ── #4 decrement 直下 ────────────────────────────────────────────────────

rDecConst = add(req4);
rDecConst.Summary     = 'デクリメント操作の列挙値定義';
rDecConst.Description = ['dec 操作の出力候補値（Dec_Short / Dec_Middle / Dec_Long）および ' ...
    '前サンプル比較用の参照値（Dec_Short / Dec_Middle / Dec_Long）を ' ...
    'EnumeratedConstant ブロックとして定義する。'];

rDecShort = add(req4);
rDecShort.Summary     = 'デクリメント短押し検出';
rDecShort.Description = ['dec_sw が true のとき reqMode.Dec_Short を出力する。' ...
    'dec_sw が false のときは else 入力（inc/dec 以外のスイッチ要求）をパススルーする。'];

rDecMid = add(req4);
rDecMid.Summary     = 'デクリメント中押し昇格判定';
rDecMid.Description = ['前サンプル要求が reqMode.Dec_Short または reqMode.Dec_Middle である' ...
    '（RelationalOperator × 2 → OR）かつ dec_sw が継続して true（AND）の場合に ' ...
    'reqMode.Dec_Middle を出力する。これによりスイッチの押し続けに伴う段階的昇格を実現する。'];

rDecLongHold = add(req4);
rDecLongHold.Summary     = 'デクリメント長押し状態の継続';
rDecLongHold.Description = ['前サンプル要求が reqMode.Dec_Long（RelationalOperator）かつ ' ...
    'dec_sw が継続して true（AND）の場合に reqMode.Dec_Long を維持する。' ...
    'これにより長押し状態を次サンプルへ引き継ぎ、スロットル連続変化を実現する。'];

%% ── #5 increment 直下 ────────────────────────────────────────────────────

rIncConst = add(req5);
rIncConst.Summary     = 'インクリメント操作の列挙値定義';
rIncConst.Description = ['inc 操作の出力候補値（Inc_Short / Inc_Middle / Inc_Long）および ' ...
    '前サンプル比較用の参照値を EnumeratedConstant ブロックとして定義する。'];

rIncShort = add(req5);
rIncShort.Summary     = 'インクリメント短押し検出';
rIncShort.Description = ['inc_sw が true のとき reqMode.Inc_Short を出力する。' ...
    'inc_sw が false のときは else 入力をパススルーする。'];

rIncMid = add(req5);
rIncMid.Summary     = 'インクリメント中押し昇格判定';
rIncMid.Description = ['前サンプル要求が reqMode.Inc_Short または reqMode.Inc_Middle である' ...
    '（RelationalOperator × 2 → OR）かつ inc_sw が継続して true（AND）の場合に ' ...
    'reqMode.Inc_Middle を出力する。'];

rIncLongHold = add(req5);
rIncLongHold.Summary     = 'インクリメント長押し状態の継続';
rIncLongHold.Description = ['前サンプル要求が reqMode.Inc_Long（RelationalOperator）かつ ' ...
    'inc_sw が継続して true（AND）の場合に reqMode.Inc_Long を維持する。'];

%% ── #6 doNot Repeat 直下 ──────────────────────────────────────────────────

rDnrType = add(req6);
rDnrType.Summary     = '繰り返し禁止対象タイプの判定';
rDnrType.Description = ['現在の要求が Cancel / Cruise / Set / ResumeReq のいずれかであるかを ' ...
    'RelationalOperator × 4 → OR で判定する。' ...
    'これらのモードは連続入力を抑制すべき "モメンタリ操作" に相当する。'];

rDnrDelay = add(req6);
rDnrDelay.Summary     = '前サンプル入力の保持（doNot Repeat）';
rDnrDelay.Description = ['1 サンプル前の入力要求（reqDrInv）を Delay で保持し、' ...
    '次サンプルの同値比較（前サンプルとの同一性チェック）に使用する。'];

rDnrRelop = add(req6);
rDnrRelop.Summary     = '前サンプルとの同値判定';
rDnrRelop.Description = ['現在の要求（reqDrInv）と Delay の出力（前サンプル）が同値かを ' ...
    'RelationalOperator で判定する。同値であれば「同一スイッチが連続して押されている」ことを示す。'];

rDnrOut = add(req6);
rDnrOut.Summary     = '重複入力時の NoRequest 出力';
rDnrOut.Description = ['繰り返し禁止対象タイプ（OR 出力）かつ前サンプルと同値（AND）の場合に ' ...
    'reqMode.NoRequest を出力する。それ以外のときは reqDrInv をパススルーする（Switch）。'];

fprintf('Requirements added: 15\n');

%% ════════════════════════════════════════════════════════════════════════
%%  Implement リンクの作成
%% ════════════════════════════════════════════════════════════════════════

totalLinks = 0;

% ── DSR トップレベル ──────────────────────────────────────────────────────

% EnumeratedConstant (blk_249~253) → rConst1
for blk = find_system(dsrPath, 'SearchDepth', 1, 'BlockType', 'EnumeratedConstant')'
    try; slreq.createLink(get_param(blk{1},'Handle'), rConst1); totalLinks=totalLinks+1; catch; end
end

% Switch (blk_254~257) → rSwPri
for blk = find_system(dsrPath, 'SearchDepth', 1, 'BlockType', 'Switch')'
    try; slreq.createLink(get_param(blk{1},'Handle'), rSwPri); totalLinks=totalLinks+1; catch; end
end

% Delay (blk_248) → rDelay1
for blk = [find_system(dsrPath, 'SearchDepth', 1, 'BlockType', 'Delay'); ...
           find_system(dsrPath, 'SearchDepth', 1, 'BlockType', 'UnitDelay')]'
    try; slreq.createLink(get_param(blk{1},'Handle'), rDelay1); totalLinks=totalLinks+1; catch; end
end

% ── decrement ─────────────────────────────────────────────────────────────

% EnumeratedConstant (blk_262~266) → rDecConst
for blk = find_system(decPath, 'SearchDepth', 1, 'BlockType', 'EnumeratedConstant')'
    try; slreq.createLink(get_param(blk{1},'Handle'), rDecConst); totalLinks=totalLinks+1; catch; end
end

% Switch の振り分け
for blk = find_system(decPath, 'SearchDepth', 1, 'BlockType', 'Switch')'
    bname = get_param(blk{1}, 'Name');
    if strcmp(bname, 'Switch1')
        tgt = rDecShort;
    elseif strcmp(bname, 'Switch6')
        tgt = rDecMid;
    elseif strcmp(bname, 'Switch4')
        tgt = req7;         % カウンタ閾値到達時に Dec_Long を選択
    elseif strcmp(bname, 'Switch_hold_long')
        tgt = rDecLongHold;
    else
        tgt = req4;
    end
    try; slreq.createLink(get_param(blk{1},'Handle'), tgt); totalLinks=totalLinks+1; catch; end
end

% RelationalOperator の振り分け
for blk = find_system(decPath, 'SearchDepth', 1, 'BlockType', 'RelationalOperator')'
    bname = get_param(blk{1}, 'Name');
    if strcmp(bname, 'relop_hold_long')
        tgt = rDecLongHold;
    else  % relop1 (Dec_Middle比較), relop14 (Dec_Short比較)
        tgt = rDecMid;
    end
    try; slreq.createLink(get_param(blk{1},'Handle'), tgt); totalLinks=totalLinks+1; catch; end
end

% Logic の振り分け
for blk = find_system(decPath, 'SearchDepth', 1, 'BlockType', 'Logic')'
    bname = get_param(blk{1}, 'Name');
    if strcmp(bname, 'LogicOp_hold_long')
        tgt = rDecLongHold;
    else  % LogicOp3 (OR), LogicOp1 (AND) → 中押し昇格
        tgt = rDecMid;
    end
    try; slreq.createLink(get_param(blk{1},'Handle'), tgt); totalLinks=totalLinks+1; catch; end
end

% counter サブシステム → req7
for blk = find_system(decPath, 'SearchDepth', 1, 'BlockType', 'SubSystem')'
    try; slreq.createLink(get_param(blk{1},'Handle'), req7); totalLinks=totalLinks+1; catch; end
end

% ── increment ─────────────────────────────────────────────────────────────

for blk = find_system(incPath, 'SearchDepth', 1, 'BlockType', 'EnumeratedConstant')'
    try; slreq.createLink(get_param(blk{1},'Handle'), rIncConst); totalLinks=totalLinks+1; catch; end
end

for blk = find_system(incPath, 'SearchDepth', 1, 'BlockType', 'Switch')'
    bname = get_param(blk{1}, 'Name');
    if strcmp(bname, 'Switch1')
        tgt = rIncShort;
    elseif strcmp(bname, 'Switch6')
        tgt = rIncMid;
    elseif strcmp(bname, 'Switch4')
        tgt = req8;
    elseif strcmp(bname, 'Switch_hold_long')
        tgt = rIncLongHold;
    else
        tgt = req5;
    end
    try; slreq.createLink(get_param(blk{1},'Handle'), tgt); totalLinks=totalLinks+1; catch; end
end

for blk = find_system(incPath, 'SearchDepth', 1, 'BlockType', 'RelationalOperator')'
    bname = get_param(blk{1}, 'Name');
    if strcmp(bname, 'relop_hold_long')
        tgt = rIncLongHold;
    else
        tgt = rIncMid;
    end
    try; slreq.createLink(get_param(blk{1},'Handle'), tgt); totalLinks=totalLinks+1; catch; end
end

for blk = find_system(incPath, 'SearchDepth', 1, 'BlockType', 'Logic')'
    bname = get_param(blk{1}, 'Name');
    if strcmp(bname, 'LogicOp_hold_long')
        tgt = rIncLongHold;
    else
        tgt = rIncMid;
    end
    try; slreq.createLink(get_param(blk{1},'Handle'), tgt); totalLinks=totalLinks+1; catch; end
end

for blk = find_system(incPath, 'SearchDepth', 1, 'BlockType', 'SubSystem')'
    try; slreq.createLink(get_param(blk{1},'Handle'), req8); totalLinks=totalLinks+1; catch; end
end

% ── doNot Repeat ──────────────────────────────────────────────────────────

for blk = find_system(dnrPath, 'SearchDepth', 1, 'BlockType', 'EnumeratedConstant')'
    val = get_param(blk{1}, 'Value');
    if contains(val, 'NoRequest')
        tgt = rDnrOut;
    else
        tgt = rDnrType;
    end
    try; slreq.createLink(get_param(blk{1},'Handle'), tgt); totalLinks=totalLinks+1; catch; end
end

for blk = [find_system(dnrPath, 'SearchDepth', 1, 'BlockType', 'Delay'); ...
           find_system(dnrPath, 'SearchDepth', 1, 'BlockType', 'UnitDelay')]'
    try; slreq.createLink(get_param(blk{1},'Handle'), rDnrDelay); totalLinks=totalLinks+1; catch; end
end

for blk = find_system(dnrPath, 'SearchDepth', 1, 'BlockType', 'RelationalOperator')'
    bname = get_param(blk{1}, 'Name');
    if strcmp(bname, 'relop4')   % current == prev
        tgt = rDnrRelop;
    else                          % relop1/2/3/14: タイプ判定用比較
        tgt = rDnrType;
    end
    try; slreq.createLink(get_param(blk{1},'Handle'), tgt); totalLinks=totalLinks+1; catch; end
end

for blk = find_system(dnrPath, 'SearchDepth', 1, 'BlockType', 'Logic')'
    op = get_param(blk{1}, 'Operator');
    if strcmp(op, 'AND')
        tgt = rDnrOut;
    else   % OR(4)
        tgt = rDnrType;
    end
    try; slreq.createLink(get_param(blk{1},'Handle'), tgt); totalLinks=totalLinks+1; catch; end
end

for blk = find_system(dnrPath, 'SearchDepth', 1, 'BlockType', 'Switch')'
    try; slreq.createLink(get_param(blk{1},'Handle'), rDnrOut); totalLinks=totalLinks+1; catch; end
end

%% ── 保存 ──────────────────────────────────────────────────────────────────

linkSets = slreq.find('Type', 'LinkSet');
for i = 1:numel(linkSets)
    save(linkSets(i));
end
save(rs);

% リンク種別の確認
allLinks = slreq.find('Type', 'Link');
nImpl = 0; nVerify = 0;
for i = 1:numel(allLinks)
    if strcmp(allLinks(i).Type, 'Implement'), nImpl = nImpl + 1;
    elseif strcmp(allLinks(i).Type, 'Verify'), nVerify = nVerify + 1;
    end
end
fprintf('Done. Implement links created: %d  (Verify links in set: %d)\n', nImpl, nVerify);
