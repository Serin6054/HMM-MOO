function out = postprocess_make_day_ahead_outputs(cfg)
% EXP-POST
% Generate day-ahead table/figures (Table3, Fig4, Fig5).

if nargin < 1 || isempty(cfg)
    cfg = local_load_cfg_from_latest();
end

out_dir = fullfile(cfg.out_root, cfg.tag);
tables_dir = fullfile(out_dir, 'tables');
figures_dir = fullfile(out_dir, 'figures');
local_ensure_dir(tables_dir);
local_ensure_dir(figures_dir);

scenarios_design = local_load_scenarios(cfg.scen_design_path, 'scenarios_design');
scenarios_test = local_load_scenarios(cfg.scen_test_path, 'scenarios_test');

case_tbl = exp_define_cases(cfg.case_list);
alpha = cfg.alpha_cvar;

% ---------- Table3 from cache_det_test ----------
ncase = height(case_tbl);
rows = cell(ncase, 8);
for i=1:ncase
    cid = char(case_tbl.case_id(i));
    cdir = fullfile(out_dir, 'per_case', cid);
    d = load(fullfile(cdir, 'cache_det_test.mat'), 'det_keep');
    det = d.det_keep;
    piw = local_get_prob(det, numel(det.L));

    rows(i,:) = {cid, char(case_tbl.case_name(i)), ...
        sum(piw .* det.J(:)), ...
        local_weighted_cvar(det.L(:), piw, alpha), ...
        sum(piw .* det.Oel(:)), ...
        sum(piw .* det.Ocmp(:)), ...
        sum(piw .* det.DW(:)), ...
        sum(piw .* det.P_TOT(:))};
end

T3 = cell2table(rows, 'VariableNames', ...
    {'case_id','case_name','mean_J','CVaR_alpha_L','mean_Oel','mean_Ocmp','mean_DW','mean_P_TOT'});
writetable(T3, fullfile(tables_dir, 'Table3_DayAhead_Summary.csv'));

% ---------- Fig4 quota heatmap for full case ----------
full_id = local_pick_full_case(case_tbl);
cdir = fullfile(out_dir, 'per_case', full_id);
da = load(fullfile(cdir, 'cache_day_ahead.mat'));
u = da.u_best(:);
R = da.R;
u_ch = u(1:R);
u_cp = u(R+1:2*R);

quota_tbl = table((1:R).', u_ch, u_cp, 'VariableNames', {'zone_idx','u_ch','u_cp'});
writetable(quota_tbl, fullfile(tables_dir, sprintf('DayAheadQuota_%s.csv', full_id)));

f4 = figure('Visible','off');
imagesc([u_ch(:)'; u_cp(:)']);
colormap(parula); colorbar;
yticks([1 2]); yticklabels({'u\_ch','u\_cp'});
xlabel('Zone index'); ylabel('Control type');
title(sprintf('Fig4 Day-ahead Quota Heatmap (%s)', full_id));
saveas(f4, fullfile(figures_dir, 'Fig4_DayAhead_QuotaHeatmap.png'));
close(f4);

% ---------- Fig5 risk tradeoff sweep (alpha sweep on full case) ----------
alpha_list = [0.80 0.85 0.90 0.95];
pt_meanJ = zeros(numel(alpha_list),1);
pt_cvar = zeros(numel(alpha_list),1);
labels = cell(numel(alpha_list),1);

for k=1:numel(alpha_list)
    ak = alpha_list(k);
    params = cfg.params_base;
    sw = local_get_case_switches(full_id);
    params.switches = sw;
    params.alpha = ak;
    params.u_mode = 'quota';
    params.infeas.mode = "proxy";

    % EXP-CACHE: reuse sweep cache when available.
    sweep_cache = fullfile(out_dir, 'cache', sprintf('risk_sweep_%s_alpha%.2f.mat', full_id, ak));
    if exist(sweep_cache,'file') == 2
        s = load(sweep_cache, 'mean_J', 'cvar_L');
        pt_meanJ(k) = s.mean_J;
        pt_cvar(k) = s.cvar_L;
    else
        u_k = solve_day_ahead_case(full_id, scenarios_design, params);
        [~, ~, ~, det_k] = eval_objectives_CVaR(u_k, scenarios_test, params);
        piw_k = local_get_prob(det_k, numel(det_k.L));
        mean_J = sum(piw_k .* det_k.J(:)); %#ok<NASGU>
        cvar_L = local_weighted_cvar(det_k.L(:), piw_k, ak); %#ok<NASGU>
        save(sweep_cache, 'u_k', 'det_k', 'mean_J', 'cvar_L', 'ak');
        pt_meanJ(k) = mean_J;
        pt_cvar(k) = cvar_L;
    end
    labels{k} = sprintf('\\alpha=%.2f', ak);
end

f5 = figure('Visible','off');
plot(pt_meanJ, pt_cvar, '-o', 'LineWidth', 1.5); grid on;
xlabel('mean_J'); ylabel('CVaR_\alpha(L)');
title(sprintf('Fig5 Risk Tradeoff (%s, alpha sweep)', full_id));
hold on;
for k=1:numel(alpha_list)
    text(pt_meanJ(k), pt_cvar(k), ['  ', labels{k}], 'FontSize', 8);
end
saveas(f5, fullfile(figures_dir, 'Fig5_RiskTradeoff_Cost_vs_CVaR.png'));
close(f5);

out = struct('table3', fullfile(tables_dir,'Table3_DayAhead_Summary.csv'), ...
             'fig4', fullfile(figures_dir,'Fig4_DayAhead_QuotaHeatmap.png'), ...
             'fig5', fullfile(figures_dir,'Fig5_RiskTradeoff_Cost_vs_CVaR.png'));
end

function cfg = local_load_cfg_from_latest()
res_root = 'results_experiments';
dd = dir(fullfile(res_root, '*'));
dd = dd([dd.isdir]);
dd = dd(~ismember({dd.name},{'.','..'}));
if isempty(dd), error('No results_experiments/* folder found.'); end
[~,ix] = max([dd.datenum]);
cfg = exp_config_template();
cfg.tag = dd(ix).name;
cache_cfg = fullfile(res_root, cfg.tag, 'cache', 'run_config.mat');
if exist(cache_cfg,'file')==2
    s = load(cache_cfg,'cfg');
    cfg = s.cfg;
end
end

function scenarios = local_load_scenarios(mat_path, var_name)
S = load(mat_path);
if isfield(S,var_name), scenarios = S.(var_name); return; end
fns = fieldnames(S);
for i=1:numel(fns)
    v = S.(fns{i});
    if isstruct(v) && isfield(v,'P_req_rt')
        scenarios = v; return;
    end
end
error('Scenario variable not found in %s', mat_path);
end

function full_id = local_pick_full_case(case_tbl)
ix = find(strcmpi(string(case_tbl.case_id), "C5"), 1, 'first');
if isempty(ix)
    full_id = char(case_tbl.case_id(end));
else
    full_id = char(case_tbl.case_id(ix));
end
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

function piw = local_get_prob(det, S)
if isfield(det,'piw') && numel(det.piw)==S
    piw = det.piw(:);
elseif isfield(det,'pi') && numel(det.pi)==S
    piw = det.pi(:);
else
    piw = ones(S,1)/S;
end
piw = piw / sum(piw);
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
