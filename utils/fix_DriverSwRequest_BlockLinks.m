%% fix_DriverSwRequest_BlockLinks.m
% DriverSwRequest ブロック → 要件の Implement リンクを正しく再作成する。
% EnumeratedConstant / UnitDelay / Switch / Logic / RelOp の
% マスクサブシステムはハンドルだけリンクし、内部は対象外とする。

rootDir = currentProject().RootFolder;

if ~bdIsLoaded('crs_controller')
    open_system(fullfile(rootDir, 'crs_controller.slx'));
    drawnow; pause(1);
end

rs   = slreq.load(fullfile(rootDir, 'crs_controller_requirements.slreqx'));

% 既存要件
req7 = find(rs, 'Type', 'Requirement', 'Id', '#7');
req8 = find(rs, 'Type', 'Requirement', 'Id', '#8');

% 新規要件（add_DriverSwRequest_BlockRequirements.m で追加済み）
rConst1      = find(rs, 'Type', 'Requirement', 'Id', '#38');
rSwPri       = find(rs, 'Type', 'Requirement', 'Id', '#39');
rDelay1      = find(rs, 'Type', 'Requirement', 'Id', '#40');
rDecConst    = find(rs, 'Type', 'Requirement', 'Id', '#41');
rDecShort    = find(rs, 'Type', 'Requirement', 'Id', '#42');
rDecMid      = find(rs, 'Type', 'Requirement', 'Id', '#43');
rDecLongHold = find(rs, 'Type', 'Requirement', 'Id', '#44');
rIncConst    = find(rs, 'Type', 'Requirement', 'Id', '#45');
rIncShort    = find(rs, 'Type', 'Requirement', 'Id', '#46');
rIncMid      = find(rs, 'Type', 'Requirement', 'Id', '#47');
rIncLongHold = find(rs, 'Type', 'Requirement', 'Id', '#48');
rDnrType     = find(rs, 'Type', 'Requirement', 'Id', '#49');
rDnrDelay    = find(rs, 'Type', 'Requirement', 'Id', '#50');
rDnrRelop    = find(rs, 'Type', 'Requirement', 'Id', '#51');
rDnrOut      = find(rs, 'Type', 'Requirement', 'Id', '#52');

dsrPath = 'crs_controller/DriverSwRequest';
decPath = [dsrPath '/decrement'];
incPath = [dsrPath '/increment'];
dnrPath = [dsrPath '/doNot Repeat'];

totalLinks = 0;

%% ── DSR トップレベル ──────────────────────────────────────────────────────

% EnumeratedConstant（マスクSubSystem）→ rConst1
blks = subsByMask(dsrPath, 'Enumerated Constant');
for i = 1:numel(blks)
    tryLink(blks{i}, rConst1); totalLinks = totalLinks + 1;
end

% Switch × 4 → rSwPri
for blk = find_system(dsrPath, 'SearchDepth', 1, 'BlockType', 'Switch')'
    tryLink(blk{1}, rSwPri); totalLinks = totalLinks + 1;
end

% Delay → rDelay1
for blk = [find_system(dsrPath,'SearchDepth',1,'BlockType','Delay'); ...
           find_system(dsrPath,'SearchDepth',1,'BlockType','UnitDelay')]'
    tryLink(blk{1}, rDelay1); totalLinks = totalLinks + 1;
end

%% ── decrement ─────────────────────────────────────────────────────────────

% EnumeratedConstant → rDecConst
blks = subsByMask(decPath, 'Enumerated Constant');
for i = 1:numel(blks)
    tryLink(blks{i}, rDecConst); totalLinks = totalLinks + 1;
end

% Switch の振り分け
for blk = find_system(decPath, 'SearchDepth', 1, 'BlockType', 'Switch')'
    switch get_param(blk{1}, 'Name')
        case 'Switch1',         tgt = rDecShort;
        case 'Switch6',         tgt = rDecMid;
        case 'Switch4',         tgt = req7;
        case 'Switch_hold_long',tgt = rDecLongHold;
        otherwise,              tgt = [];
    end
    if ~isempty(tgt); tryLink(blk{1}, tgt); totalLinks = totalLinks + 1; end
end

% RelationalOperator の振り分け
for blk = find_system(decPath, 'SearchDepth', 1, 'BlockType', 'RelationalOperator')'
    if strcmp(get_param(blk{1},'Name'), 'relop_hold_long')
        tgt = rDecLongHold;
    else
        tgt = rDecMid;
    end
    tryLink(blk{1}, tgt); totalLinks = totalLinks + 1;
end

% Logic の振り分け
for blk = find_system(decPath, 'SearchDepth', 1, 'BlockType', 'Logic')'
    if strcmp(get_param(blk{1},'Name'), 'LogicOp_hold_long')
        tgt = rDecLongHold;
    else
        tgt = rDecMid;
    end
    tryLink(blk{1}, tgt); totalLinks = totalLinks + 1;
end

% counter（SLDV counter マスクSubSystem）→ req7
blks = subsByMask(decPath, 'SLDV counter');
for i = 1:numel(blks)
    tryLink(blks{i}, req7); totalLinks = totalLinks + 1;
end

%% ── increment ─────────────────────────────────────────────────────────────

blks = subsByMask(incPath, 'Enumerated Constant');
for i = 1:numel(blks)
    tryLink(blks{i}, rIncConst); totalLinks = totalLinks + 1;
end

for blk = find_system(incPath, 'SearchDepth', 1, 'BlockType', 'Switch')'
    switch get_param(blk{1}, 'Name')
        case 'Switch1',         tgt = rIncShort;
        case 'Switch6',         tgt = rIncMid;
        case 'Switch4',         tgt = req8;
        case 'Switch_hold_long',tgt = rIncLongHold;
        otherwise,              tgt = [];
    end
    if ~isempty(tgt); tryLink(blk{1}, tgt); totalLinks = totalLinks + 1; end
end

for blk = find_system(incPath, 'SearchDepth', 1, 'BlockType', 'RelationalOperator')'
    if strcmp(get_param(blk{1},'Name'), 'relop_hold_long')
        tgt = rIncLongHold;
    else
        tgt = rIncMid;
    end
    tryLink(blk{1}, tgt); totalLinks = totalLinks + 1;
end

for blk = find_system(incPath, 'SearchDepth', 1, 'BlockType', 'Logic')'
    if strcmp(get_param(blk{1},'Name'), 'LogicOp_hold_long')
        tgt = rIncLongHold;
    else
        tgt = rIncMid;
    end
    tryLink(blk{1}, tgt); totalLinks = totalLinks + 1;
end

blks = subsByMask(incPath, 'SLDV counter');
for i = 1:numel(blks)
    tryLink(blks{i}, req8); totalLinks = totalLinks + 1;
end

%% ── doNot Repeat ──────────────────────────────────────────────────────────

% EnumeratedConstant: NoRequest → rDnrOut, 他 → rDnrType
blks = subsByMask(dnrPath, 'Enumerated Constant');
for i = 1:numel(blks)
    val = get_param(blks{i}, 'Value');
    if contains(val, 'NoRequest')
        tgt = rDnrOut;
    else
        tgt = rDnrType;
    end
    tryLink(blks{i}, tgt); totalLinks = totalLinks + 1;
end

% Delay → rDnrDelay
for blk = [find_system(dnrPath,'SearchDepth',1,'BlockType','Delay'); ...
           find_system(dnrPath,'SearchDepth',1,'BlockType','UnitDelay')]'
    tryLink(blk{1}, rDnrDelay); totalLinks = totalLinks + 1;
end

% RelationalOperator: relop4 → rDnrRelop, 他 → rDnrType
for blk = find_system(dnrPath, 'SearchDepth', 1, 'BlockType', 'RelationalOperator')'
    if strcmp(get_param(blk{1},'Name'), 'relop4')
        tgt = rDnrRelop;
    else
        tgt = rDnrType;
    end
    tryLink(blk{1}, tgt); totalLinks = totalLinks + 1;
end

% Logic: AND → rDnrOut, OR → rDnrType
for blk = find_system(dnrPath, 'SearchDepth', 1, 'BlockType', 'Logic')'
    if strcmp(get_param(blk{1},'Operator'), 'AND')
        tgt = rDnrOut;
    else
        tgt = rDnrType;
    end
    tryLink(blk{1}, tgt); totalLinks = totalLinks + 1;
end

% Switch → rDnrOut
for blk = find_system(dnrPath, 'SearchDepth', 1, 'BlockType', 'Switch')'
    tryLink(blk{1}, rDnrOut); totalLinks = totalLinks + 1;
end

%% ── 保存 ──────────────────────────────────────────────────────────────────

linkSets = slreq.find('Type', 'LinkSet');
for i = 1:numel(linkSets)
    save(linkSets(i));
end
save(rs);

fprintf('Implement links created: %d\n', totalLinks);

% 種別サマリ
allLinks = slreq.find('Type', 'Link');
nImpl    = sum(strcmp({allLinks.Type}, 'Implement'));
nVerify  = sum(strcmp({allLinks.Type}, 'Verify'));
fprintf('  Implement: %d,  Verify: %d\n', nImpl, nVerify);

%% ── ローカル関数 ─────────────────────────────────────────────────────────

function blks = subsByMask(parentPath, maskType)
    % MaskType でフィルタリングしたマスクSubSystemのパス配列を返す
    all  = find_system(parentPath, 'SearchDepth', 1, 'BlockType', 'SubSystem');
    all  = all(2:end);  % コンテナ自身（先頭）を除外
    mt   = cellfun(@(b) get_param(b, 'MaskType'), all, 'UniformOutput', false);
    blks = all(strcmp(mt, maskType));
end

function tryLink(blkPath, req)
    try
        slreq.createLink(get_param(blkPath, 'Handle'), req);
    catch e
        fprintf('  WARN: %s — %s\n', blkPath, e.message);
    end
end
