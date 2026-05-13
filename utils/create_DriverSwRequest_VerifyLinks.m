%% create_DriverSwRequest_VerifyLinks.m
% DriverSwRequest MCDC テストケースと crs_controller_requirements の
% 要件の間に "Verified By" (Verify) リンクを作成する。

rootDir = currentProject().RootFolder;

slreq.clear();

% テストファイルに紐付くリンクセットファイルを削除してクリーンな状態にする
slmxPath = fullfile(rootDir, 'tests', 'DriverSwRequest_MCDC_Tests~mldatx.slmx');
if exist(slmxPath, 'file')
    delete(slmxPath);
    fprintf('Deleted stale link set: %s\n', slmxPath);
end

rs = slreq.load(fullfile(rootDir, 'crs_controller_requirements.slreqx'));

req1 = find(rs, 'Type', 'Requirement', 'Id', '#1');   % DriverSwRequest
req4 = find(rs, 'Type', 'Requirement', 'Id', '#4');   % decrement
req5 = find(rs, 'Type', 'Requirement', 'Id', '#5');   % increment
req6 = find(rs, 'Type', 'Requirement', 'Id', '#6');   % doNot Repeat
req7 = find(rs, 'Type', 'Requirement', 'Id', '#7');   % counter (decrement)
req8 = find(rs, 'Type', 'Requirement', 'Id', '#8');   % counter (increment)

tf2 = sltest.testmanager.load(fullfile(rootDir, 'tests', 'DriverSwRequest_MCDC_Tests.mldatx'));
suites = tf2.getTestSuites();
ts2 = [];
for i = 1:numel(suites)
    if strcmp(suites(i).Name, 'DriverSwRequest_MCDC_Suite')
        ts2 = suites(i); break;
    end
end
tcs = ts2.getTestCases();

tcMap = containers.Map();
for i = 1:numel(tcs)
    tcMap(tcs(i).Name) = i;
end

% {テストケース名, 要件インデックス配列}
linkMap = {
    'TC01_NoInput',              [1];
    'TC02_Cancel',               [1];
    'TC03_Cruise',               [1];
    'TC04_Set',                  [1];
    'TC05_Resume',               [1];
    'TC06_PriorCncl',            [1];
    'TC07_PriorEnbl',            [1];
    'TC08_PriorSet',             [1];
    'TC09_PriorResume',          [1];
    'TC10_CnclRepeat',           [1 6];
    'TC11_CruiseRepeat',         [1 6];
    'TC12_SetRepeat',            [1 6];
    'TC13_ResumeRepeat',         [1 6];
    'TC14_IncNoSuppress',        [1 6];
    'TC15_DecShort',             [1 4];
    'TC16_DecOff',               [1 4];
    'TC17_DecMiddle_fromShort',  [1 4];
    'TC18_DecMiddle_fromMiddle', [1 4];
    'TC19_DecMiddle_LogicFalse', [1 4];
    'TC20_DecLong_Counter',      [1 4 7];
    'TC21_DecLong_Hold',         [1 4 7];
    'TC22_DecLong_Release',      [1 4];
    'TC23_DecShort_HoldFalse',   [1 4];
    'TC24_IncShort',             [1 5];
    'TC25_IncOff',               [1 5];
    'TC26_IncMiddle_fromShort',  [1 5];
    'TC27_IncMiddle_fromMiddle', [1 5];
    'TC28_IncLogic1_False',      [1 5];
    'TC29_IncLong_Counter',      [1 5 8];
    'TC30_IncLong_Hold',         [1 5 8];
    'TC31_IncLong_Release',      [1 5];
    'TC32_IncShort_HoldFalse',   [1 5];
};

reqObjs = {req1, [], [], req4, req5, req6, req7, req8};

totalLinks = 0;
for row = 1:size(linkMap, 1)
    tcName  = linkMap{row, 1};
    reqIdxs = linkMap{row, 2};
    tc = tcs(tcMap(tcName));
    for kk = 1:numel(reqIdxs)
        lnk = slreq.createLink(tc, reqObjs{reqIdxs(kk)});
        totalLinks = totalLinks + 1;
    end
end

linkSets = slreq.find('Type', 'LinkSet');
for i = 1:numel(linkSets)
    save(linkSets(i));
end
save(rs);

fprintf('Verify links created: %d\n', totalLinks);

% リンク型の確認
allLinks = slreq.find('Type', 'Link');
nVerify    = 0;
nImplement = 0;
nOther     = 0;
for i = 1:numel(allLinks)
    lt = allLinks(i).Type;
    if strcmp(lt, 'Verify')
        nVerify = nVerify + 1;
    elseif strcmp(lt, 'Implement')
        nImplement = nImplement + 1;
    else
        nOther = nOther + 1;
    end
end
fprintf('  Verify: %d, Implement: %d, Other: %d\n', nVerify, nImplement, nOther);
