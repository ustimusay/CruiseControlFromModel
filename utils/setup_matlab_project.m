%% setup_matlab_project.m
% CruiseControlFromModel を MATLAB Project として設定する。
% utils/, tests/, reports/, data/ をプロジェクトパスに追加する。

projRoot = 'C:\work\demos\CruiseControlFromModel';

prjFile = fullfile(projRoot, 'CruiseControlFromModel.prj');
if exist(prjFile, 'file')
    proj = openProject(prjFile);
    fprintf('Opened existing project: %s\n', prjFile);
else
    proj = matlab.project.createProject('Folder', projRoot, 'Name', 'CruiseControlFromModel');
    fprintf('Created new project: %s\n', prjFile);
end

foldersToAdd = {'data', 'tests', 'reports', 'utils'};
for i = 1:numel(foldersToAdd)
    folderPath = fullfile(projRoot, foldersToAdd{i});
    if exist(folderPath, 'dir')
        try
            proj.addPath(folderPath);
            fprintf('Added to project path: %s\n', foldersToAdd{i});
        catch e
            fprintf('Path already added or error: %s — %s\n', foldersToAdd{i}, e.message);
        end
    else
        fprintf('Folder does not exist, skipping: %s\n', foldersToAdd{i});
    end
end

fprintf('\nProject root: %s\n', proj.RootFolder);
fprintf('Setup complete.\n');
