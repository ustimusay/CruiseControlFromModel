%% add_FrontDistanceAutoEnable_Requirements.m
% Add requirements and Implement links for the front-distance automatic
% Enable transition added to CruiseControlMode/opMode.

rootDir = currentProject().RootFolder;
modelName = 'crs_controller';
reqSetPath = fullfile(rootDir, 'crs_controller_requirements.slreqx');

slreq.clear;

if ~bdIsLoaded(modelName)
    open_system(fullfile(rootDir, [modelName '.slx']));
    drawnow; pause(1);
end

rs = slreq.load(reqSetPath);
rOpMode = find(rs, 'Type', 'Requirement', 'Id', '#12');
if isempty(rOpMode)
    error('Requirement #12 opMode was not found in %s.', reqSetPath);
end

thresholdReq = 'FrontDistanceThreshold_mm (5000 mm)';

reqInterface = getOrCreateReq(rs, rOpMode, ...
    'frontDistance single入力の受け渡し', ...
    ['The CruiseControlMode shall accept the forward vehicle distance as a single-precision ', ...
     'frontDistance input in millimeters and provide it to opMode for mode transition decisions.'], ...
    ['The distance sensor is a new external controller input. Passing it through the top model, ', ...
     'CruiseControlMode, and opMode preserves the existing subsystem ownership while making the ', ...
     'signal available to the mode-selection logic.'], ...
    {'draft','frontDistance','interface','auto-enable'});

reqThreshold = getOrCreateReq(rs, rOpMode, ...
    'frontDistance 5m閾値判定', ...
    ['When frontDistance is less than or equal to ', thresholdReq, ...
     ', the CruiseControlMode shall assert the forward-distance-near condition.'], ...
    ['The 5 m threshold represents the requested following-distance boundary. Using the ', ...
     'Data Dictionary Simulink.Parameter FrontDistanceThreshold_mm avoids embedding a literal ', ...
     'threshold in the model and keeps calibration ownership outside the block diagram.'], ...
    {'draft','frontDistance','threshold','auto-enable'});

reqAutoEnable = getOrCreateReq(rs, rOpMode, ...
    'Activate中の前方距離による自動Enable遷移', ...
    ['While the operation mode is opMode.Activate, when frontDistance is less than or equal to ', ...
     thresholdReq, ', the CruiseControlMode shall transition the operation mode to opMode.Enable.'], ...
    ['Returning from Activate to Enable when a forward vehicle is detected within 5 m prevents ', ...
     'continued active cruise throttle control while preserving the enabled standby state for ', ...
     'subsequent driver action. The added condition is ORed with the existing enableCondition so ', ...
     'driver-requested Enable behavior is retained.'], ...
    {'draft','frontDistance','mode-transition','auto-enable'});

reqNoFalseEnable = getOrCreateReq(rs, rOpMode, ...
    '非Activate状態または5m超過時の自動Enable抑止', ...
    ['If the operation mode is not opMode.Activate or frontDistance is greater than ', ...
     thresholdReq, ', then frontDistance shall not independently command a transition to opMode.Enable.'], ...
    ['Gating the distance threshold with opMode.Activate prevents a near-distance sensor reading ', ...
     'from changing Disable, Enable, Resume, Increment, or Decrement modes unexpectedly. This keeps ', ...
     'the added behavior scoped to the active cruise-control state.'], ...
    {'draft','frontDistance','mode-transition','auto-enable'});

linkCount = 0;
linkCount = linkCount + linkIfMissing('crs_controller/frontDistance', reqInterface);
linkCount = linkCount + linkIfMissing('crs_controller/CruiseControlMode/frontDistance', reqInterface);
linkCount = linkCount + linkIfMissing('crs_controller/CruiseControlMode/opMode/frontDistance', reqInterface);

linkCount = linkCount + linkIfMissing('crs_controller/CruiseControlMode/opMode/FrontDistanceThreshold_mm', reqThreshold);
linkCount = linkCount + linkIfMissing('crs_controller/CruiseControlMode/opMode/frontDistanceWithin5m', reqThreshold);

linkCount = linkCount + linkIfMissing('crs_controller/CruiseControlMode/opMode/modeIsActivate', reqAutoEnable);
linkCount = linkCount + linkIfMissing('crs_controller/CruiseControlMode/opMode/autoEnableCondition', reqAutoEnable);
linkCount = linkCount + linkIfMissing('crs_controller/CruiseControlMode/opMode/enableConditionOrAuto', reqAutoEnable);
linkCount = linkCount + linkIfMissing('crs_controller/CruiseControlMode/opMode/Switch3', reqAutoEnable);

linkCount = linkCount + linkIfMissing('crs_controller/CruiseControlMode/opMode/modeIsActivate', reqNoFalseEnable);
linkCount = linkCount + linkIfMissing('crs_controller/CruiseControlMode/opMode/frontDistanceWithin5m', reqNoFalseEnable);
linkCount = linkCount + linkIfMissing('crs_controller/CruiseControlMode/opMode/autoEnableCondition', reqNoFalseEnable);

linkSets = slreq.find('Type', 'LinkSet');
for i = 1:numel(linkSets)
    save(linkSets(i));
end
save(rs);
save_system(modelName);

fprintf('Front-distance auto Enable requirements updated. New Implement links: %d\n', linkCount);
fprintf('Requirement IDs: %s, %s, %s, %s\n', ...
    reqInterface.Id, reqThreshold.Id, reqAutoEnable.Id, reqNoFalseEnable.Id);

function req = getOrCreateReq(reqSet, parentReq, summary, description, rationale, keywords)
    allReqs = find(reqSet, 'Type', 'Requirement');
    req = [];
    for i = 1:numel(allReqs)
        try
            if ~isempty(allReqs(i).Parent) && strcmp(allReqs(i).Parent.Id, parentReq.Id) && strcmp(allReqs(i).Summary, summary)
                req = allReqs(i);
                break;
            end
        catch
        end
    end
    if isempty(req)
        req = add(parentReq, 'Type', 'Functional');
    end
    req.Summary = summary;
    req.Description = description;
    req.Rationale = rationale;
    try
        req.Keywords = keywords;
    catch
    end
end

function created = linkIfMissing(blockPath, req)
    created = 0;
    h = get_param(blockPath, 'Handle');
    links = slreq.outLinks(h);
    for i = 1:numel(links)
        try
            if strcmp(links(i).Type, 'Implement') && strcmp(links(i).getDestinationLabel, req.Summary)
                return;
            end
        catch
        end
    end
    slreq.createLink(h, req);
    created = 1;
end
