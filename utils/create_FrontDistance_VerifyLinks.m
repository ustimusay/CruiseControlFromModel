%% create_FrontDistance_VerifyLinks.m
% Create Verify links from the front-distance CruiseControlMode MCDC tests
% to the related requirements.

rootDir = currentProject().RootFolder;
reqSetPath = fullfile(rootDir, 'crs_controller_requirements.slreqx');
testFilePath = fullfile(rootDir, 'tests', 'CruiseControlMode_MCDC_Tests.mldatx');

slreq.clear;

rs = slreq.load(reqSetPath);
tf = sltest.testmanager.load(testFilePath);

suites = tf.getAllTestSuites();
testSuite = [];
for i = 1:numel(suites)
    if strcmp(suites(i).Name, 'CruiseControlMode_MCDC_Suite')
        testSuite = suites(i);
        break;
    end
end
if isempty(testSuite)
    error('CruiseControlMode_MCDC_Suite was not found.');
end

tcs = testSuite.getTestCases();
tcMap = containers.Map();
for i = 1:numel(tcs)
    tcMap(tcs(i).Name) = i;
end

reqIds = {'#236', '#237', '#238', '#239'};
reqs = containers.Map();
for i = 1:numel(reqIds)
    req = find(rs, 'Type', 'Requirement', 'Id', reqIds{i});
    if isempty(req)
        error('Requirement %s was not found.', reqIds{i});
    end
    reqs(reqIds{i}) = req;
end

linkMap = {
    'TC48_FrontDistanceAutoEnable',     {'#236', '#237', '#238'};
    'TC49_FrontDistanceAboveThreshold', {'#236', '#237', '#239'};
};

created = 0;
existing = 0;
for row = 1:size(linkMap, 1)
    tcName = linkMap{row, 1};
    if ~isKey(tcMap, tcName)
        error('Test case %s was not found.', tcName);
    end

    tc = tcs(tcMap(tcName));
    ids = linkMap{row, 2};
    for k = 1:numel(ids)
        req = reqs(ids{k});
        if hasVerifyLink(tc, req)
            existing = existing + 1;
        else
            slreq.createLink(tc, req);
            created = created + 1;
        end
    end
end

linkSets = slreq.find('Type', 'LinkSet');
for i = 1:numel(linkSets)
    save(linkSets(i));
end
save(rs);

fprintf('Front-distance Verify links created: %d, already existing: %d\n', created, existing);

for row = 1:size(linkMap, 1)
    tcName = linkMap{row, 1};
    tc = tcs(tcMap(tcName));
    links = slreq.outLinks(tc);
    fprintf('  %s\n', tcName);
    for i = 1:numel(links)
        if strcmp(links(i).Type, 'Verify')
            fprintf('    Verify -> %s %s\n', links(i).destination.id, links(i).getDestinationLabel);
        end
    end
end

function tf = hasVerifyLink(tc, req)
    tf = false;
    links = slreq.outLinks(tc);
    for i = 1:numel(links)
        try
            if strcmp(links(i).Type, 'Verify') && strcmp(links(i).destination.id, req.Id)
                tf = true;
                return;
            end
        catch
        end
    end
end
