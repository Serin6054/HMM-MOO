function step3_run_main_results_minimal(varargin)
    p = inputParser;
    p.addParameter('cache_dir','cache',@(s)ischar(s)||isstring(s));
    p.addParameter('out_dir',fullfile('results','main_caseA'),@(s)ischar(s)||isstring(s));
    p.addParameter('proposed_entrypoint','',@(s)ischar(s)||isstring(s));
    p.parse(varargin{:});
    opt = p.Results;

    if ~exist(opt.out_dir,'dir'), mkdir(opt.out_dir); end

    sc_design = load_scenarios_any(fullfile(opt.cache_dir,'scenarios_design.mat'));
    sc_test   = load_scenarios_any(fullfile(opt.cache_dir,'scenarios_test.mat'));

    % Load params if exists
    params = struct();
    params_file = fullfile(opt.cache_dir,'params0.mat');
    if exist(params_file,'file')==2
        tmp = load(params_file);
        if isfield(tmp,'params0'), params = tmp.params0; end
        if isfield(tmp,'params'),  params = tmp.params;  end
    end
    if ~isfield(params,'alpha'), params.alpha = 0.90; end
    if ~isfield(params,'dt'),    params.dt    = 1; end

    % ---- diurnal shaping (for two-stage effect under 2R controls) ----
    [s_ev, s_cp] = compute_inverse_shapes_from_design(sc_design, 0.3, 3.0, 2.0);
    params.ev_shape = s_ev;
    params.cp_shape = s_cp;

    T = numel(params.ev_shape);
ramp = linspace(0.8, 1.2, T);   % 前低后高
params.ev_shape = params.ev_shape(:)'.*ramp;  params.ev_shape = params.ev_shape/mean(params.ev_shape);
params.cp_shape = params.cp_shape(:)'.*ramp;  params.cp_shape = params.cp_shape/mean(params.cp_shape);

    % default main results: run system in two-stage recourse mode
    if ~isfield(params,'switches') || ~isstruct(params.switches)
        params.switches = struct();
    end
    params.switches.two_stage = 1;

    rows = {};

    % ---- Fixed baseline ----
    try
        u_fixed = solve_day_ahead_fixed(sc_design, params, struct('alpha',params.alpha));
        [f1,f2,cvar,det] = eval_objectives_CVaR_plus(u_fixed, sc_test, params);
        rows(end+1,:) = {'Fixed-Quantile', f1, f2, cvar, det.feasible_rate, det.mean_cost, 'OK'}; %#ok<AGROW>
    catch ME
        rows(end+1,:) = {'Fixed-Quantile', NaN, NaN, NaN, NaN, NaN, ['FAIL: ' ME.message]}; %#ok<AGROW>
    end

    % ---- Proposed ----
    try
        if ~isempty(opt.proposed_entrypoint)
            u_prop = solve_day_ahead_proposed(sc_design, params, struct('entrypoint',char(opt.proposed_entrypoint)));
        else
            u_prop = solve_day_ahead_proposed(sc_design, params, struct());
        end
        [f1,f2,cvar,det] = eval_objectives_CVaR_plus(u_prop, sc_test, params);
        rows(end+1,:) = {'Proposed', f1, f2, cvar, det.feasible_rate, det.mean_cost, 'OK'}; %#ok<AGROW>
    catch ME
        rows(end+1,:) = {'Proposed', NaN, NaN, NaN, NaN, NaN, ['FAIL: ' ME.message]}; %#ok<AGROW>
        fprintf('[MainResults] Proposed skipped/failed: %s\n', ME.message);
    end

    T = cell2table(rows, 'VariableNames', {'Method','f1','f2','CVaR','feasible','mean_cost','status'});
    out_csv = fullfile(opt.out_dir,'main_results.csv');
    writetable(T, out_csv);
    fprintf('[MainResults] Saved: %s\n', out_csv);
end

function sc = load_scenarios_any(matfile)
    assert(exist(matfile,'file')==2, 'Cannot find: %s', matfile);
    tmp = load(matfile);
    cand = {'scenarios_test','scenarios_design','scenarios','scens','sc'};
    sc = [];
    for i=1:numel(cand)
        if isfield(tmp,cand{i})
            sc = tmp.(cand{i});
            break;
        end
    end
    assert(~isempty(sc), 'No scenarios variable found in %s', matfile);
end