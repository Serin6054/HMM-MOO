function step2_export_setup_tables(varargin)
%STEP2_EXPORT_SETUP_TABLES Export Table 1 (system & dataset) and Table 2 (params) to CSV.
%
% After step1b split, run:
%   step2_export_setup_tables
%
% Outputs will be saved to results/setup_tables/.

p = inputParser;
addParameter(p, 'cache_dir', 'cache', @(s)ischar(s) || isstring(s));
addParameter(p, 'out_dir', fullfile('results','setup_tables'), @(s)ischar(s) || isstring(s));
parse(p, varargin{:});
cache_dir = char(p.Results.cache_dir);
out_dir = char(p.Results.out_dir);

addpath(genpath('utils'));
if ~isfolder(out_dir)
    mkdir(out_dir);
end

out = load_scenarios_split('cache_dir', cache_dir);
meta = struct();
params = struct();
if isfield(out,'meta'); meta = out.meta; end
if isfield(out,'params'); params = out.params; end

% --- Table 1: system & dataset ---
T1 = {};
T1(end+1,:) = {'Testbed / Case', get_field(meta, 'case_name', 'Case A/B')};
T1(end+1,:) = {'Network model', get_field(meta, 'network', 'IEEE 33-bus / 118-bus')};
T1(end+1,:) = {'# Zones (R)', num2str(get_field_num(meta, 'R', NaN))};
T1(end+1,:) = {'Horizon (T)', num2str(get_field_num(meta, 'T', 24))};
T1(end+1,:) = {'Slot length (Δt)', num2str(get_field_num(meta, 'dt', 1))};
T1(end+1,:) = {'# Day-ahead scenarios', num2str(get_field_num(out, 'S_design', NaN))};
T1(end+1,:) = {'# Test scenarios', num2str(get_field_num(out, 'S_test', NaN))};

% Data source strings if present
T1(end+1,:) = {'EV demand source', get_field(meta, 'ev_source', 'volume.csv (kept unchanged)')};
T1(end+1,:) = {'Compute workload source', get_field(meta, 'compute_source', 'synthetic proxy (diurnal + noise + tail)')};

% Basic stats from scenarios
if isfield(out,'scenarios_design') && ~isempty(out.scenarios_design)
    stats = basic_stats(out.scenarios_design);
    T1(end+1,:) = {'EV request (kW) range', sprintf('[%.3g, %.3g]', stats.Pmin, stats.Pmax)};
    if ~isnan(stats.Wmax)
        T1(end+1,:) = {'Compute request range', sprintf('[%.3g, %.3g]', stats.Wmin, stats.Wmax)};
    end
end

writecell([{'Item','Value'}; T1], fullfile(out_dir, 'Table1_System_and_Dataset.csv'));

% --- Table 2: params ---
T2 = {};
% weights
T2 = append_if_exists(T2, params, 'lambda1', 'Objective weight λ1');
T2 = append_if_exists(T2, params, 'lambda2', 'Objective weight λ2');
T2 = append_if_exists(T2, params, 'lambda3', 'Objective weight λ3');

% penalties
T2 = append_if_exists(T2, params, 'beta_J', 'Penalty β_J');
T2 = append_if_exists(T2, params, 'beta_el', 'Penalty β_el');
T2 = append_if_exists(T2, params, 'beta_cmp', 'Penalty β_cmp');

% risk
T2 = append_if_exists(T2, params, 'alpha', 'CVaR level α');
T2 = append_if_exists(T2, params, 'risk_weight', 'Risk weight β');

% compute proxy
T2 = append_if_exists(T2, params, 's_W', 'Workload scale s_W');
T2 = append_if_exists(T2, params, 'kappa_F', 'Compute power factor κ_F');
T2 = append_if_exists(T2, params, 'P_idle_ref', 'Edge idle power (ref)');
T2 = append_if_exists(T2, params, 'P_peak_ref', 'Edge peak power (ref)');

% algorithm
T2 = append_if_exists(T2, params, 'n_particles', '# Particles');
T2 = append_if_exists(T2, params, 'n_iter', '# Iterations');
T2 = append_if_exists(T2, params, 'n_seeds', '# Seeds');
T2 = append_if_exists(T2, params, 'kf_q', 'Kalman Q');
T2 = append_if_exists(T2, params, 'kf_r', 'Kalman R');

% OPF
T2 = append_if_exists(T2, params, 'opf_solver', 'OPF/PowerFlow solver');
T2 = append_if_exists(T2, params, 'vmin', 'Voltage min');
T2 = append_if_exists(T2, params, 'vmax', 'Voltage max');

if isempty(T2)
    T2 = {'(no params fields detected)', ''};
end

writecell([{'Parameter','Value'}; T2], fullfile(out_dir, 'Table2_Params_and_Reproducibility.csv'));

fprintf('[SetupTables] Exported to %s\n', out_dir);
end

function v = get_field(S, name, default)
if isstruct(S) && isfield(S, name)
    v = S.(name);
    if isstring(v) || ischar(v)
        v = char(v);
    else
        v = to_str(v);
    end
else
    v = default;
end
end

function v = get_field_num(S, name, default)
if isstruct(S) && isfield(S, name) && isnumeric(S.(name))
    v = S.(name);
else
    v = default;
end
end

function s = to_str(x)
if isnumeric(x)
    if isscalar(x)
        s = num2str(x);
    else
        s = mat2str(x);
    end
elseif islogical(x)
    s = mat2str(x);
else
    s = '<value>';
end
end

function T2 = append_if_exists(T2, params, field, label)
if isstruct(params) && isfield(params, field)
    T2(end+1,:) = {label, to_str(params.(field))};
end
end

function stats = basic_stats(scens)
stats.Pmin = inf; stats.Pmax = -inf;
stats.Wmin = inf; stats.Wmax = -inf;
for i=1:numel(scens)
    sc = scens(i);
    if isfield(sc,'P_EV_req')
        P = sc.P_EV_req;
    elseif isfield(sc,'P_req_rt')
        P = sc.P_req_rt;
    else
        P = [];
    end
    if ~isempty(P)
        stats.Pmin = min(stats.Pmin, min(P(:)));
        stats.Pmax = max(stats.Pmax, max(P(:)));
    end
    if isfield(sc,'lambda_req_rt')
        W = sc.lambda_req_rt;
        stats.Wmin = min(stats.Wmin, min(W(:)));
        stats.Wmax = max(stats.Wmax, max(W(:)));
    end
end
if isinf(stats.Wmin); stats.Wmin = NaN; end
if isinf(stats.Wmax); stats.Wmax = NaN; end
end
