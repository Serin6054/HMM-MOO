function out = run_experiments(cfg)
%RUN_EXPERIMENTS Main experiment entry, outputs Table2 + Table4 + per-scenario CSVs.

if nargin < 1 || isempty(cfg)
    cfg = exp_config_template();
end

if ~isfield(cfg,'params_base') || isempty(cfg.params_base)
    cfg.params_base = oracle_make_params();
end

out_dir = fullfile(cfg.out_root, cfg.tag);
per_case_dir = fullfile(out_dir, 'per_case');
tables_dir = fullfile(out_dir, 'tables');
figures_dir = fullfile(out_dir, 'figures');
cache_dir = fullfile(out_dir, 'cache');

local_ensure_dir(cfg.out_root);
local_ensure_dir(out_dir);
local_ensure_dir(per_case_dir);
local_ensure_dir(tables_dir);
local_ensure_dir(figures_dir);
local_ensure_dir(cache_dir);

scenarios_design = local_load_scenarios(cfg.scen_design_path, 'scenarios_design');
scenarios_test = local_load_scenarios(cfg.scen_test_path, 'scenarios_test');

if isfield(cfg, 'split_path') && exist(cfg.split_path,'file') == 2
    try
        splitData = load(cfg.split_path, 'split'); %#ok<NASGU>
    catch
    end
end

case_tbl = exp_define_cases(cfg.case_list);
writetable(case_tbl, fullfile(out_dir, 'Table2_CaseMatrix.csv')); % compat
writetable(case_tbl, fullfile(tables_dir, 'Table2_CaseMatrix.csv'));

save(fullfile(cache_dir, 'run_config.mat'), 'cfg'); % EXP-CACHE

ncase = height(case_tbl);
rows = cell(ncase, 12);

for i = 1:ncase
    cid = string(case_tbl.case_id(i));
    cname = string(case_tbl.case_name(i));

    sw = local_get_case_switches(cid);
    params = cfg.params_base;
    params.switches = sw;
    params.alpha = cfg.alpha_cvar;
    params.u_mode = 'quota'; % EXP-U-SCALE

    params = local_configure_infeas(params, sw, cfg);

    t_start = tic;
    u = solve_day_ahead_case(char(cid), scenarios_design, params);
    [~, ~, f3, det] = eval_objectives_CVaR(u, scenarios_test, params);
    [flaginf_s, ~] = oracle_compute_infeasibility(u, scenarios_test, det, params);
    runtime_sec = toc(t_start);

    piw = local_get_probabilities(det, numel(scenarios_test));
    scen_idx = (1:numel(scenarios_test)).';

    % EXP-METRIC: stable per-scenario output fields
    per_tbl = table(scen_idx, piw, det.J(:), det.Oel(:), det.Ocmp(:), det.L(:), ...
                    det.P_TOT(:), det.DW(:), double(flaginf_s(:)), ...
                    'VariableNames', {'scen_idx','pi','J','Oel','Ocmp','L','P_TOT','DW','flaginf'});

    case_subdir = fullfile(per_case_dir, char(cid));
    local_ensure_dir(case_subdir);
    writetable(per_tbl, fullfile(case_subdir, 'per_scenario_metrics.csv'));

    % EXP-CACHE: stable cached day-ahead + test-eval artifacts for postprocess.
    u_best = u; %#ok<NASGU>
    params_used = params; %#ok<NASGU>
    R = scenarios_test(1).R; %#ok<NASGU>
    T = scenarios_test(1).T; %#ok<NASGU>
    alpha = cfg.alpha_cvar; %#ok<NASGU>
    save(fullfile(case_subdir, 'cache_day_ahead.mat'), 'u_best', 'params_used', 'sw', 'R', 'T', 'alpha');

    det_keep = struct();
    det_keep.J = det.J(:);
    det_keep.Oel = det.Oel(:);
    det_keep.Ocmp = det.Ocmp(:);
    det_keep.L = det.L(:);
    det_keep.DW = det.DW(:);
    det_keep.P_TOT = det.P_TOT(:);
    det_keep.piw = piw(:);
    if isfield(det,'eta'), det_keep.eta = det.eta; else, det_keep.eta = NaN; end
    save(fullfile(case_subdir, 'cache_det_test.mat'), 'det_keep');

    mean_J = sum(piw .* det.J(:));
    cvar_L_alpha = local_weighted_cvar(det.L(:), piw, cfg.alpha_cvar);
    mean_Oel = sum(piw .* det.Oel(:));
    p95_Oel = local_weighted_quantile(det.Oel(:), piw, 0.95);
    mean_DW = sum(piw .* det.DW(:));
    infeas_rate = mean(flaginf_s);

    rows(i,:) = {'IEEE33', char(cid), char(cname), mean_J, cvar_L_alpha, mean_Oel, ...
                 p95_Oel, mean_DW, infeas_rate, runtime_sec, f3, char(string(params.infeas.mode))};
end

summary_tbl = cell2table(rows, 'VariableNames', ...
    {'net_name','case_id','case_name','mean_J','cvar_L_alpha','mean_Oel','p95_Oel', ...
     'mean_DW','infeas_rate','runtime_sec','f3_eval','infeas_mode'});
writetable(summary_tbl, fullfile(out_dir, 'Table4_Summary.csv')); % compat
writetable(summary_tbl, fullfile(tables_dir, 'Table4_Summary.csv'));

out = struct();
out.out_dir = out_dir;
out.tables_dir = tables_dir;
out.figures_dir = figures_dir;
out.cache_dir = cache_dir;
out.table2 = fullfile(tables_dir, 'Table2_CaseMatrix.csv');
out.table4 = fullfile(tables_dir, 'Table4_Summary.csv');
out.summary = summary_tbl;
end

function scenarios = local_load_scenarios(mat_path, var_name)
if exist(mat_path,'file') ~= 2
    error('Missing scenario cache: %s', mat_path);
end

S = load(mat_path);
if isfield(S, var_name)
    scenarios = S.(var_name);
    return;
end

fns = fieldnames(S);
for i = 1:numel(fns)
    v = S.(fns{i});
    if isstruct(v) && ~isempty(v) && isfield(v,'P_req_rt') && isfield(v,'lambda_req_rt')
        scenarios = v;
        return;
    end
end

error('No valid scenario variable found in %s', mat_path);
end

function params = local_configure_infeas(params, sw, cfg)
params.infeas.enable = true;
params.infeas.mode = "proxy";

if logical(sw.opf) && isfield(cfg,'use_opf') && cfg.use_opf
    if local_has_matpower()
        params.infeas.mode = "opf";
        params.infeas.opf.case_path = fullfile('data','case33bw.m');
        params.infeas.opf.map_csv = fullfile('data','zone_to_bus.csv');
    else
        warning('run_experiments:opfFallback', 'MATPOWER not found, fallback to proxy infeasibility mode.');
    end
end
end

function tf = local_has_matpower()
tf = (exist('runopf','file') == 2 || exist('rundcopf','file') == 2 || exist('runpf','file') == 2);
end

function piw = local_get_probabilities(det, S)
if isfield(det,'piw') && numel(det.piw) == S
    piw = det.piw(:);
elseif isfield(det,'pi') && numel(det.pi) == S
    piw = det.pi(:);
else
    piw = ones(S,1) / S;
end
piw = piw / sum(piw);
end

function sw = local_get_case_switches(case_id)
if exist('get_case_switches','file') == 2
    sw = get_case_switches(case_id);
elseif exist('utils.get_case_switches','file') == 2
    sw = feval('utils.get_case_switches', case_id);
else
    error('Cannot locate get_case_switches.m');
end
end

function q = local_weighted_quantile(x, w, alpha)
x = x(:); w = w(:);
w = w / sum(w);
[xs, idx] = sort(x, 'ascend');
ws = w(idx);
cdf = cumsum(ws);
k = find(cdf >= alpha, 1, 'first');
if isempty(k), k = numel(xs); end
q = xs(k);
end

function cvar = local_weighted_cvar(x, w, alpha)
eta = local_weighted_quantile(x, w, alpha);
cvar = eta + (1/(1-alpha)) * sum(w(:) .* max(x(:)-eta, 0));
end

function local_ensure_dir(d)
if exist(d,'dir') ~= 7
    mkdir(d);
end
end
