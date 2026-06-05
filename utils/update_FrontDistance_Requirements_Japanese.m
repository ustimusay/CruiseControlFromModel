%% update_FrontDistance_Requirements_Japanese.m
% Rewrite the front-distance requirement descriptions and rationales in
% Japanese while preserving requirement IDs, summaries, and trace links.

rootDir = currentProject().RootFolder;
reqSetPath = fullfile(rootDir, 'crs_controller_requirements.slreqx');

rs = slreq.load(reqSetPath);

updates = {
    '#236', ...
    'CruiseControlMode は、前方車両との距離をミリメートル単位の single 型 frontDistance 入力として受け取り、モード遷移判定に使用できるよう opMode へ受け渡さなければならない。', ...
    '前方距離センサーは新規の外部入力である。トップモデル、CruiseControlMode、opMode を通して信号を受け渡すことで、既存のサブシステム責務を保ったままモード選択ロジックで距離情報を利用できるようにするため。';
    '#237', ...
    'frontDistance が FrontDistanceThreshold_mm (5000 mm) 以下のとき、CruiseControlMode は前方車両が5 m以内に存在する状態として判定しなければならない。', ...
    '5 m は要求された前方車両距離の境界値である。閾値を Data Dictionary の Simulink.Parameter である FrontDistanceThreshold_mm として管理することで、モデル内の直値を避け、キャリブレーション値の管理箇所を明確にするため。';
    '#238', ...
    '動作モードが opMode.Activate の間に frontDistance が FrontDistanceThreshold_mm (5000 mm) 以下になった場合、CruiseControlMode は動作モードを opMode.Enable へ遷移させなければならない。', ...
    '前方車両が5 m以内に検出された場合に Activate から Enable へ戻すことで、アクティブなクルーズ制御を継続しない一方、運転者の次操作に備えた Enable 状態を維持するため。追加条件は既存の enableCondition と OR 結合しており、従来の運転者要求による Enable 遷移を保持する。';
    '#239', ...
    '動作モードが opMode.Activate ではない場合、または frontDistance が FrontDistanceThreshold_mm (5000 mm) を超える場合、frontDistance は単独で opMode.Enable への遷移を指令してはならない。', ...
    '距離閾値判定を opMode.Activate 状態でゲートすることで、近距離のセンサー値によって Disable、Enable、Resume、Increment、Decrement などの他モードが意図せず変化することを防ぐため。追加機能の影響範囲をアクティブなクルーズ制御状態に限定する。'
};

for i = 1:size(updates, 1)
    req = find(rs, 'Type', 'Requirement', 'Id', updates{i,1});
    if isempty(req)
        error('Requirement %s was not found.', updates{i,1});
    end
    req.Description = updates{i,2};
    req.Rationale = updates{i,3};
    fprintf('Updated %s: %s\n', req.Id, req.Summary);
end

save(rs);
linkSets = slreq.find('Type', 'LinkSet');
for i = 1:numel(linkSets)
    save(linkSets(i));
end
