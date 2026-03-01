function out = postprocess_make_setup_outputs(cfg)
% EXP-POST
% Generate setup-related tables/figures (Table1, Fig1-Fig3).

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

% ---------- Table 1 ----------
[R, T] = size(scenarios_design(1).P_req_rt);
dt = local_getfield_default(scenarios_design(1), 'dt', 1);

mpc = local_load_case33();
nb = size(mpc.bus,1);
nl = size(mpc.branch,1);

S1 = numel(scenarios_design);
S2 = numel(scenarios_test);

[ev_mean, ev_peak] = local_dataset_stats(scenarios_design, 'P_req_rt');
[wl_mean, wl_peak] = local_dataset_stats(scenarios_design, 'lambda_req_rt');
[pe_min, pe_max, pe_mean] = local_price_stats(scenarios_design);
[idle_min, idle_max, peak_min, peak_max] = local_edge_power_stats(scenarios_design);

item = {
    'Network';
    'Zones/Horizon/dt';
    '#Design scenarios';
    '#Test scenarios';
    'EV demand stats (sum_z P_req_rt)';
    'Workload stats (sum_z lambda_req_rt)';
    'Price_e stats';
    'Edge power model';
    'Quota vector dimension'
    };
value = {
    sprintf('IEEE-33, buses=%d, branches=%d', nb, nl);
    sprintf('R=%d, T=%d, dt=%.4g', R, T, dt);
    sprintf('%d', S1);
    sprintf('%d', S2);
    sprintf('mean=%.4f, peak=%.4f', ev_mean, ev_peak);
    sprintf('mean=%.4f, peak=%.4f', wl_mean, wl_peak);
    sprintf('min=%.4f, max=%.4f, mean=%.4f', pe_min, pe_max, pe_mean);
    sprintf('Pedge\\_idle:[%.4f, %.4f], Pedge\\_peak:[%.4f, %.4f]', idle_min, idle_max, peak_min, peak_max);
    sprintf('2R = %d', 2*R)
    };

T1 = table(item, value);
writetable(T1, fullfile(tables_dir, 'Table1_System_and_Dataset.csv'));

% ---------- Fig1 Input Curves ----------
idx_rep = local_pick_representative_idx(scenarios_design);
sc = scenarios_design(idx_rep);
pev = sum(sc.P_req_rt,1);
wl = sum(sc.lambda_req_rt,1);
pe = local_get_price_curve(sc, T);

f1 = figure('Visible','off');
subplot(2,1,1);
plot(1:T, pev, 'b-', 'LineWidth', 1.5); hold on;
plot(1:T, pe, 'r--', 'LineWidth', 1.2);
grid on;
xlabel('t'); ylabel('EV / price');
legend({'sum_z P\_req\_rt','price\_e'}, 'Location','best');
title(sprintf('Fig1 InputCurves: scen=%d, EVpeak=%.3f, EVenergy=%.3f', idx_rep, max(pev), sum(pev)*dt));

subplot(2,1,2);
plot(1:T, wl, 'k-', 'LineWidth', 1.5); grid on;
xlabel('t'); ylabel('sum_z \lambda\_req\_rt');
title(sprintf('Workload curve: WLpeak=%.3f, WLsum=%.3f', max(wl), sum(wl)));

saveas(f1, fullfile(figures_dir, 'Fig1_InputCurves.png'));
close(f1);

% ---------- Fig2 Typical Scenarios ----------
idxs = local_pick_typical_indices(scenarios_design);
f2 = figure('Visible','off');
subplot(2,1,1); hold on;
for k = 1:numel(idxs)
    y = sum(scenarios_design(idxs(k)).P_req_rt,1);
    plot(1:T, y, 'LineWidth', 1.2);
end
grid on; xlabel('t'); ylabel('sum_z P\_req\_rt');
legend(local_idx_labels(idxs), 'Location','best');
title('Fig2 TypicalScenarios - EV aggregate');

subplot(2,1,2); hold on;
for k = 1:numel(idxs)
    y = sum(scenarios_design(idxs(k)).lambda_req_rt,1);
    plot(1:T, y, 'LineWidth', 1.2);
end
grid on; xlabel('t'); ylabel('sum_z \lambda\_req\_rt');
legend(local_idx_labels(idxs), 'Location','best');
title('Fig2 TypicalScenarios - Workload aggregate');

saveas(f2, fullfile(figures_dir, 'Fig2_TypicalScenarios.png'));
close(f2);

% ---------- Fig3 IEEE33 Zone-Bus Map ----------
map = readmatrix(fullfile('data','zone_to_bus.csv'));
zone_id = map(:,1);
bus_id = map(:,2);

f3 = figure('Visible','off');
G = graph(mpc.branch(:,1), mpc.branch(:,2));
p = plot(G, 'Layout', 'force', 'MarkerSize', 3, 'NodeLabel', {});
hold on;

[~, loc] = ismember(bus_id, mpc.bus(:,1));
valid = loc > 0;
zone_bus_nodes = loc(valid);
hz = highlight(p, zone_bus_nodes, 'NodeColor', 'r', 'MarkerSize', 6);
set(hz, 'LineStyle', 'none');

for i = 1:numel(zone_bus_nodes)
    n = zone_bus_nodes(i);
    text(p.XData(n), p.YData(n), sprintf(' z%d->b%d', zone_id(valid(i)), bus_id(valid(i))), ...
        'FontSize', 8, 'Color', [0.1 0.1 0.1]);
end

title('Fig3 IEEE33 Zone-Bus Map');
saveas(f3, fullfile(figures_dir, 'Fig3_IEEE33_ZoneBusMap.png'));
close(f3);

out = struct('table1', fullfile(tables_dir,'Table1_System_and_Dataset.csv'), ...
             'fig1', fullfile(figures_dir,'Fig1_InputCurves.png'), ...
             'fig2', fullfile(figures_dir,'Fig2_TypicalScenarios.png'), ...
             'fig3', fullfile(figures_dir,'Fig3_IEEE33_ZoneBusMap.png'));
end

function cfg = local_load_cfg_from_latest()
res_root = 'results_experiments';
d = dir(res_root);
d = d([d.isdir]);
name = {d.name};
name = name(~ismember(name,{'.','..'}));
if isempty(name), error('No results_experiments/* folder found.'); end
dd = dir(fullfile(res_root, '*'));
dd = dd([dd.isdir]);
dd = dd(~ismember({dd.name},{'.','..'}));
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

function [m, p] = local_dataset_stats(scens, fld)
S = numel(scens);
tot = zeros(S,1);
pk = zeros(S,1);
for s=1:S
    x = scens(s).(fld);
    agg = sum(x,1);
    tot(s) = sum(agg);
    pk(s) = max(agg);
end
m = mean(tot);
p = max(pk);
end

function [vmin, vmax, vmean] = local_price_stats(scens)
arr = [];
for s=1:numel(scens)
    p = local_get_price_curve(scens(s), size(scens(s).P_req_rt,2));
    arr = [arr, p(:).']; %#ok<AGROW>
end
vmin = min(arr); vmax = max(arr); vmean = mean(arr);
end

function [idle_min, idle_max, peak_min, peak_max] = local_edge_power_stats(scens)
idle = []; peak = [];
for s=1:numel(scens)
    if isfield(scens(s),'Pedge_idle'), idle = [idle; scens(s).Pedge_idle(:)]; end %#ok<AGROW>
    if isfield(scens(s),'Pedge_peak'), peak = [peak; scens(s).Pedge_peak(:)]; end %#ok<AGROW>
end
if isempty(idle), idle = 0; end
if isempty(peak), peak = idle; end
idle_min = min(idle); idle_max = max(idle);
peak_min = min(peak); peak_max = max(peak);
end

function pe = local_get_price_curve(sc, T)
if isfield(sc,'price_e')
    pe = sc.price_e(:).';
elseif isfield(sc,'price')
    pe = sc.price(:).';
else
    pe = zeros(1,T);
end
if numel(pe) ~= T
    pe = pe(1) * ones(1,T);
end
end

function idx = local_pick_representative_idx(scens)
S = numel(scens);
score = zeros(S,1);
for s=1:S
    ev = sum(scens(s).P_req_rt(:));
    wl = sum(scens(s).lambda_req_rt(:));
    score(s) = ev + wl;
end
[~,ord] = sort(score);
idx = ord(round((S+1)/2));
end

function idxs = local_pick_typical_indices(scens)
S = numel(scens);
metric = zeros(S,1);
peakv = zeros(S,1);
for s=1:S
    agg = sum(scens(s).P_req_rt,1);
    metric(s) = sum(agg);
    peakv(s) = max(agg);
end
[ms, ord] = sort(metric);
q10 = ord(max(1, round(0.10*S)));
q50 = ord(max(1, round(0.50*S)));
q90 = ord(max(1, round(0.90*S)));
[~,ip] = max(peakv);
idxs = unique([q10,q50,q90,ip], 'stable');
if numel(idxs)<4
    need = setdiff(1:S, idxs, 'stable');
    idxs = [idxs, need(1:min(4-numel(idxs), numel(need)))];
end
end

function labels = local_idx_labels(idxs)
labels = cell(1,numel(idxs));
for i=1:numel(idxs)
    labels{i} = sprintf('scen-%d', idxs(i));
end
end

function mpc = local_load_case33()
addpath('data');
if exist('loadcase','file')==2
    mpc = loadcase(fullfile('data','case33bw.m'));
else
    mpc = case33bw();
end
end

function v = local_getfield_default(s, f, d)
if isfield(s,f), v = s.(f); else, v = d; end
end

function local_ensure_dir(d)
if exist(d,'dir') ~= 7
    mkdir(d);
end
end
