function step4_run_ablation_matrix(varargin)
%STEP4_RUN_ABLATION_MATRIX
% Run the ablation study and export results as CSV.
%
% 5-case ablation ladder:
%   C1 Baseline
%   C2 + Coupling
%   C3 + CVaR
%   C4 + OPF
%   C5 Full (Proposed)
%
% This version ALSO exports coupling explainability stats (if available):
%   - coupling_edge_overload_rate: fraction of (zone,slot) where overload happens
%     ONLY when including edge power (P_edge)
%   - coupling_edge_energy_share: edge energy share in (EV+edge) energy

    p = inputParser;
    p.addParameter('cache_dir','cache',@(s)ischar(s)||isstring(s));
    p.addParameter('out_dir',fullfile('results','ablation_caseA'),@(s)ischar(s)||isstring(s));
    p.addParameter('proposed_entrypoint','',@(s)ischar(s)||isstring(s));
    p.parse(varargin{:});
    opt = p.Results;

    if ~exist(opt.out_dir,'dir'), mkdir(opt.out_dir); end

    sc_design = load_scenarios_any(fullfile(opt.cache_dir,'scenarios_design.mat'));
    sc_test   = load_scenarios_any(fullfile(opt.cache_dir,'scenarios_test.mat'));

    % ---- load params (optional) ----
    params = struct();
    params_file = fullfile(opt.cache_dir,'params0.mat');
    if exist(params_file,'file')==2
        tmp = load(params_file);
        if isfield(tmp,'params0'), params = tmp.params0; end
        if isfield(tmp,'params'),  params = tmp.params;  end
    end
    if ~isfield(params,'alpha'), params.alpha = 0.90; end
    if ~isfield(params,'dt'),    params.dt    = 1; end

    % ---- diurnal shaping (2R -> pseudo 24h envelope) ----
    [s_ev, s_cp] = compute_inverse_shapes_from_design(sc_design, 0.3, 3.0, 2.0);
    params.ev_shape = s_ev;
    params.cp_shape = s_cp;

    % Optional: late-ramp (helps backlog recourse; keep consistent for all cases)
    Tshape = numel(params.ev_shape);
    ramp = linspace(0.8, 1.2, Tshape);   % early-low, late-high
    params.ev_shape = params.ev_shape(:)'.*ramp;  params.ev_shape = params.ev_shape/mean(params.ev_shape);
    params.cp_shape = params.cp_shape(:)'.*ramp;  params.cp_shape = params.cp_shape/mean(params.cp_shape);

    % ---- 5-case ablation ladder ----
    cases = {'C1','C2','C3','C4','C5'};
    rows = {};

    for i = 1:numel(cases)
        cname = cases{i};

        % Prefer shared mapper if present (utils/get_case_switches.m)
        sw = get_case_switches(cname);

        % IMPORTANT: pass switches into params for evaluation/simulation
        params_case = params;
        params_case.switches = sw;

        try
            if i <= 4
                % baseline family (C1..C4)
                u = solve_day_ahead_fixed(sc_design, params_case, struct('alpha',params_case.alpha,'switches',sw));
            else
                % full proposed family (C5)
                if ~isempty(opt.proposed_entrypoint)
                    u = solve_day_ahead_proposed(sc_design, params_case, struct('entrypoint',char(opt.proposed_entrypoint),'switches',sw));
                else
                    u = solve_day_ahead_proposed(sc_design, params_case, struct('switches',sw));
                end
            end

            [f1,f2,cvar,det] = eval_objectives_CVaR_plus(u, sc_test, params_case);

            % ---- coupling explainability (optional) ----
            cor = NaN;  % coupling_edge_overload_rate
            ces = NaN;  % coupling_edge_energy_share
            if isfield(det,'coupling_edge_overload_rate')
                cor = det.coupling_edge_overload_rate;
            end
            if isfield(det,'coupling_edge_energy_share')
                ces = det.coupling_edge_energy_share;
            end

            rows(end+1,:) = {cname, f1, f2, cvar, det.feasible_rate, det.mean_cost, cor, ces, 'OK'}; %#ok<AGROW>
        catch ME
            rows(end+1,:) = {cname, NaN, NaN, NaN, NaN, NaN, NaN, NaN, ['FAIL: ' ME.message]}; %#ok<AGROW>
        end
    end

    Tout = cell2table(rows, 'VariableNames', ...
        {'Case','f1','f2','CVaR','feasible','mean_cost','coupling_edge_overload_rate','coupling_edge_energy_share','status'});
    out_csv = fullfile(opt.out_dir,'ablation_results.csv');
    writetable(Tout, out_csv);
    fprintf('[Ablation] Saved: %s\n', out_csv);
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
