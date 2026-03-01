function rebuild_and_plot_caseA_distributions_v3(res_mat, scenarios_test_mat)
%REBUILD_AND_PLOT_CASEA_DISTRIBUTIONS_V3
% Rebuild per-scenario distributions on HOLD-OUT test scenarios using the best quota u
% stored inside RES.<METHOD>, then plot CDF + boxplots.
%
% This version avoids relying on RES.methods (which may be nested cells/structs).
%
% Usage:
%   rebuild_and_plot_caseA_distributions_v3( ...
%     'results/caseA_main_xxx/caseA_main_results.mat', ...
%     'cache/scenarios_test.mat');
%
% Outputs:
%   <res_folder>/figs_dist_rebuilt_v3/*.png + *.pdf
%   <res_folder>/figs_dist_rebuilt_v3/pooled_test_samples.mat

    if nargin < 2 || isempty(scenarios_test_mat)
        scenarios_test_mat = 'cache/scenarios_test.mat';
    end

    A = load(res_mat, 'RES');
    RES = A.RES;

    B = load(scenarios_test_mat);
    if isfield(B,'scenarios_test')
        scenarios_test = B.scenarios_test;
    elseif isfield(B,'scenarios')
        scenarios_test = B.scenarios;
    else
        error('Cannot find scenarios_test/scenarios in %s', scenarios_test_mat);
    end

    R = scenarios_test(1).R;
    dim = 2*R;
    fprintf('[Rebuild-v3] R=%d, dim=%d\n', R, dim);

    % -------- determine method blocks from RES fields --------
    fns = fieldnames(RES);

    % prefer explicit methods if present
    pref = {'RN_Plain','RN_Full','RA_Plain','RA_Full'};
    methods = pref(ismember(pref, fns));

    % otherwise infer by prefix patterns
    if isempty(methods)
        methods = {};
        for i = 1:numel(fns)
            fn = fns{i};
            if startsWith(fn,'RN_') || startsWith(fn,'RA_') || startsWith(fn,'MA_') || startsWith(fn,'PSO')
                methods{end+1} = fn; %#ok<AGROW>
            end
        end
    end

    if isempty(methods)
        error('No method blocks found in RES. Available fields: %s', strjoin(fns',', '));
    end

    fprintf('[Rebuild-v3] methods: %s\n', strjoin(methods, ', '));

    % -------- extract best u from each method block --------
    pool = struct();
    for i = 1:numel(methods)
        mname = methods{i};
        block = RES.(mname);

        [u, where] = find_best_u(block, dim);
        if isempty(u)
            error('No quota vector u found in RES.%s. (searched recursively for numeric vectors length=%d)', mname, dim);
        end
        fprintf('  - %s: found u at %s\n', mname, where);

        % simulate on test scenarios
        S = numel(scenarios_test);
        cost = zeros(S,1);
        EL   = zeros(S,1);
        CL   = zeros(S,1);
        dev  = zeros(S,1);
        wait = zeros(S,1);

        for s = 1:S
            mm = sim_one_scenario(u, scenarios_test(s));
            cost(s) = mm.cost;
            EL(s)   = mm.peak_el;
            CL(s)   = mm.peak_cl;
            dev(s)  = mm.deviation;
            wait(s) = mm.waiting;
        end

        pool(i).method = mname;
        pool(i).u = u;
        pool(i).cost = cost;
        pool(i).EL = EL;
        pool(i).CL = CL;
        pool(i).EL_over = max(EL-1,0);
        pool(i).CL_over = max(CL-1,0);
        pool(i).dev = dev;
        pool(i).wait = wait;
    end

    out_dir = fullfile(fileparts(res_mat), 'figs_dist_rebuilt_v3');
    if ~exist(out_dir,'dir'), mkdir(out_dir); end

    % save pooled samples
    save(fullfile(out_dir,'pooled_test_samples.mat'), 'pool', 'methods', 'res_mat', 'scenarios_test_mat');

    % ---- Plot helpers ----
    labels = string({pool.method});

    % CDF: CL_over
    fig = figure('Color','w'); hold on; grid on;
    for i = 1:numel(pool)
        [f,x] = ecdf(pool(i).CL_over);
        plot(x,f,'LineWidth',1.5);
    end
    xlabel('Compute overload: max(CL - 1, 0)');
    ylabel('Empirical CDF');
    legend(labels, 'Interpreter','none','Location','best');
    title('Case A (test): CDF of compute overload');
    export_fig(fig, fullfile(out_dir,'cdf_CL_over')); close(fig);

    % CDF: EL_over
    fig = figure('Color','w'); hold on; grid on;
    for i = 1:numel(pool)
        [f,x] = ecdf(pool(i).EL_over);
        plot(x,f,'LineWidth',1.5);
    end
    xlabel('Electrical overload: max(EL - 1, 0)');
    ylabel('Empirical CDF');
    legend(labels, 'Interpreter','none','Location','best');
    title('Case A (test): CDF of electrical overload');
    export_fig(fig, fullfile(out_dir,'cdf_EL_over')); close(fig);

    % Boxplot: CL_over
    X=[]; G=[];
    for i=1:numel(pool)
        x = pool(i).CL_over(:);
        X = [X; x]; %#ok<AGROW>
        G = [G; i*ones(numel(x),1)]; %#ok<AGROW>
    end
    fig = figure('Color','w');
    boxplot(X,G,'Labels',labels,'LabelOrientation','inline');
    grid on;
    ylabel('Compute overload: max(CL - 1, 0)');
    title('Case A (test): boxplot of compute overload');
    export_fig(fig, fullfile(out_dir,'box_CL_over')); close(fig);

    % Boxplot: cost
    X=[]; G=[];
    for i=1:numel(pool)
        x = pool(i).cost(:);
        X = [X; x]; %#ok<AGROW>
        G = [G; i*ones(numel(x),1)]; %#ok<AGROW>
    end
    fig = figure('Color','w');
    boxplot(X,G,'Labels',labels,'LabelOrientation','inline');
    grid on;
    ylabel('Cost (Yuan)');
    title('Case A (test): boxplot of cost');
    export_fig(fig, fullfile(out_dir,'box_cost')); close(fig);

    fprintf('Done. Figures saved to: %s\n', out_dir);
end

% ========================= recursive best-u finder =========================

function [u, where] = find_best_u(x, dim)
% Search recursively for a numeric vector length=dim, with common field priorities.

    u = [];
    where = "";

    if ~isstruct(x)
        return;
    end

    % 1) common direct fieldnames (highest priority)
    direct = {'u_best','best_u','u_star','u_opt','u','Ubest','U_best','U'};
    for k = 1:numel(direct)
        fn = direct{k};
        if isfield(x,fn)
            cand = x.(fn);
            [u, where2] = coerce_u(cand, dim, fn);
            if ~isempty(u)
                where = where2;
                return;
            end
        end
    end

    % 2) search one level deeper for "best" sub-structs
    subc = {'best','Best','solution','sol','result','out','test','eval'};
    for k = 1:numel(subc)
        fn = subc{k};
        if isfield(x,fn) && isstruct(x.(fn))
            [u, where2] = find_best_u(x.(fn), dim);
            if ~isempty(u)
                where = fn + "." + where2;
                return;
            end
        end
    end

    % 3) brute recursive scan over all struct fields
    fns = fieldnames(x);
    for i = 1:numel(fns)
        fn = fns{i};
        v = x.(fn);
        if isstruct(v)
            [u, where2] = find_best_u(v, dim);
            if ~isempty(u)
                where = fn + "." + where2;
                return;
            end
        else
            [u, where2] = coerce_u(v, dim, fn);
            if ~isempty(u)
                where = where2;
                return;
            end
        end
    end
end

function [u, where] = coerce_u(v, dim, hint)
% Convert candidate v into a 1xdim row vector u, if possible.
    u = [];
    where = "";

    if isempty(v) || ~isnumeric(v)
        return;
    end

    % vector case
    if isvector(v) && numel(v) == dim
        u = v(:)'; where = hint; return;
    end

    % matrix case: pick a row/col of length dim
    [nr,nc] = size(v);
    if nr == dim && nc ~= dim
        u = v(:,end)'; where = hint + "(:,end)"; return;
    end
    if nc == dim && nr ~= dim
        u = v(end,:); where = hint + "(end,:)"; return;
    end

    % matrix where one dimension is dim: pick last slice
    if nr == dim && nc == dim
        u = v(end,:); where = hint + "(end,:)"; return;
    end

    % sometimes it's stored as a long vector with extra bookkeeping; take first dim
    if isvector(v) && numel(v) > dim
        u = v(1:dim); where = hint + "(1:dim)"; return;
    end
end

function export_fig(fig, basepath)
    set(fig,'InvertHardcopy','off');
    print(fig, basepath + ".png", "-dpng", "-r300");
    print(fig, basepath + ".pdf", "-dpdf");
end
