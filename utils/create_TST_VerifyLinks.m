%% create_TST_VerifyLinks.m
% TST_MCDC_Tests の各テストケースと crs_controller_requirements の
% TargetSpeedThrottle 配下要件の間に "Verify" リンクを作成する。

rootDir = currentProject().RootFolder;
slreq.clear();

slmxPath = fullfile(rootDir, 'tests', 'TST_MCDC_Tests~mldatx.slmx');
if isfile(slmxPath)
    delete(slmxPath);
    fprintf('Deleted stale link set: %s\n', slmxPath);
end

rs  = slreq.load(fullfile(rootDir, 'crs_controller_requirements.slreqx'));
tf2 = sltest.testmanager.load(fullfile(rootDir, 'tests', 'TST_MCDC_Tests.mldatx'));

suites = tf2.getTestSuites();
ts2 = [];
for i = 1:numel(suites)
    if strcmp(suites(i).Name, 'TST_MCDC_Suite')
        ts2 = suites(i); break;
    end
end
tcs = ts2.getTestCases();
tcMap = containers.Map();
for i = 1:numel(tcs)
    tcMap(tcs(i).Name) = i;
end

% ── 要件オブジェクトの取得 ─────────────────────────────────────────
r = @(id) find(rs, 'Type', 'Requirement', 'Id', id);

rTST   = r('#3');    % TargetSpeedThrottle Container

% toBoolean
rTB    = r('#181');  rTB_EC_Dis=r('#191'); rTB_EC_Res=r('#192'); rTB_EC_En=r('#193');
rTB_r1 = r('#194');  rTB_r2=r('#195');     rTB_r3=r('#196');     rTB_NOR=r('#197');

% disabled
rDis   = r('#182');  rDis_C=r('#198');

% enabled
rEn    = r('#183');

% targetSpeed
rTS    = r('#184');  rSS=r('#185');
rTS_UD1=r('#199');   rTS_L1=r('#200'); rTS_Sw5=r('#201');

% activated
rAct   = r('#186');

% getNewTargetSpeed
rGNTS  = r('#187');
rGNTS_EC_Act=r('#202'); rGNTS_EC_IncH=r('#203');
rGNTS_EC_Inc=r('#204'); rGNTS_EC_Dec=r('#205');
rGNTS_Ci_s=r('#206');   rGNTS_Ci_h=r('#207');
rGNTS_Cd_s=r('#208');   rGNTS_Cd_h=r('#209');
rGNTS_A1=r('#210');     rGNTS_A2=r('#211');
rGNTS_A3=r('#212');     rGNTS_A4=r('#213');
rGNTS_R1=r('#214');     rGNTS_R2=r('#215');
rGNTS_R3=r('#216');     rGNTS_R4=r('#217');
rGNTS_Sw=r('#218');     rGNTS_Sw1=r('#219');
rGNTS_Sw2=r('#220');    rGNTS_Sw3=r('#221');
rGNTS_Sat=r('#222');

% getThrottleValue / PI controller / UsePI
rGTV   = r('#188');  rPI=r('#189');  rUsePI=r('#190');
rPI_A=r('#223');     rPI_D=r('#224'); rPI_K=r('#225'); rPI_S=r('#226');
rUPI_rs=r('#227');   rUPI_rR=r('#228'); rUPI_L=r('#229');
rGTV_D1=r('#230');   rGTV_Sw=r('#231'); rGTV_Sat=r('#232');

% top-level
rMerge=r('#233'); rMerge1=r('#234'); rUD=r('#235');

% ── {テストケース名, 要件オブジェクト配列} ──────────────────────────
linkMap = {
    'TC01_Disable',  {rTST,rTB,rDis,rTB_EC_Dis,rTB_r1,rTB_NOR,rDis_C,rMerge,rMerge1,rUD};
    'TC02_Enable',   {rTST,rTB,rEn,rTB_EC_En,rTB_r2,rTB_NOR,rMerge,rMerge1,rUD};
    'TC03_Activate', {rTST,rTB,rAct,rGNTS,rTB_NOR,rGNTS_EC_Act,rGNTS_R2,rGNTS_Sw,rMerge,rMerge1,rUD};
    'TC04_Resume',   {rTB,rTB_EC_Res,rTB_r3,rTB_NOR,rTS,rSS,rTS_UD1,rTS_L1,rTS_Sw5,rMerge,rMerge1,rUD};
    'TC05_LogicOp1_prevActFalse', {rTS,rTS_UD1,rTS_L1};
    'TC06_LogicOp1_enFalse',      {rTS,rTS_UD1,rTS_L1};
    'TC07_Increment',    {rGNTS,rGNTS_EC_Inc,rGNTS_Ci_s,rGNTS_A1,rGNTS_R2,rGNTS_R1,rGNTS_Sw,rGNTS_Sw1};
    'TC08_IncrementHold',{rGNTS,rGNTS_EC_IncH,rGNTS_Ci_h,rGNTS_A2,rGNTS_R1,rGNTS_R3,rGNTS_Sw1,rGNTS_Sw2};
    'TC09_Decrement',    {rGNTS,rGNTS_EC_Dec,rGNTS_Cd_s,rGNTS_A3,rGNTS_R3,rGNTS_R4,rGNTS_Sw2,rGNTS_Sw3};
    'TC10_DecrementHold',{rGNTS,rGNTS_Cd_h,rGNTS_A4,rGNTS_R4,rGNTS_Sw3};
    'TC11_SatLow',   {rGNTS,rGNTS_Sat,rGNTS_R4,rGNTS_A3};
    'TC12_SatHigh',  {rGNTS,rGNTS_Sat,rGNTS_Ci_s,rGNTS_A1,rGNTS_R1};
    'TC13_UsePITrue',    {rAct,rGTV,rPI,rUsePI,rPI_A,rPI_D,rPI_K,rPI_S,rUPI_rs,rUPI_rR,rUPI_L,rGTV_D1,rGTV_Sw,rGTV_Sat};
    'TC14_UsePI_relpFalse',  {rUsePI,rUPI_rs,rUPI_L,rGTV_Sw};
    'TC15_UsePI_RelOpFalse', {rUsePI,rUPI_rR,rUPI_L,rGTV_Sw};
    'TC16_Sat2Lower',        {rGTV,rGTV_Sw,rGTV_Sat};
};

totalLinks = 0;
for row = 1:size(linkMap, 1)
    tcName  = linkMap{row, 1};
    reqList = linkMap{row, 2};
    tc = tcs(tcMap(tcName));
    for kk = 1:numel(reqList)
        try
            slreq.createLink(tc, reqList{kk});
            totalLinks = totalLinks + 1;
        catch e
            warning('Link failed TC=%s req=%s: %s', tcName, reqList{kk}.Id, e.message);
        end
    end
end

linkSets = slreq.find('Type', 'LinkSet');
for i = 1:numel(linkSets)
    save(linkSets(i));
end
save(rs);

fprintf('Verify links created: %d\n', totalLinks);

allLinks = slreq.find('Type', 'Link');
nV=0; nI=0;
for i = 1:numel(allLinks)
    if strcmp(allLinks(i).Type,'Verify'),    nV=nV+1;
    elseif strcmp(allLinks(i).Type,'Implement'), nI=nI+1; end
end
fprintf('  Verify: %d, Implement: %d\n', nV, nI);
