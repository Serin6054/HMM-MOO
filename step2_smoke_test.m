function step2_smoke_test(varargin)
%STEP2_SMOKE_TEST Quick end-to-end check after step1b split.
%
% This script:
%   1) loads scenarios_design/test from cache
%   2) evaluates a default u0 (loaded if available; otherwise constructs a safe envelope)
%   3) prints key metrics and basic field checks
%
% NOTE:
%   Your current eval_objectives_CVaR requires length(u) == 2R (one EV envelope
%   and one compute envelope per zone, time-invariant). This smoke test builds
%   a compatible u0 if none exists in cache.

p = inputParser;
addParameter(p, 'cache_dir', 'cache', @(s)ischar(s) || isstring(s));
addParameter(p, 'n_scen', 10, @(x)isnumeric(x) && x>=1);
parse(p, varargin{:});
cache_dir = char(p.Results.cache_dir);
n_scen = p.Results.n_scen;

addpath(genpath('utils'));

out = load_scenarios_split('cache_dir', cache_dir);
assert(isfield(out,'scenarios_test') && ~isempty(out.scenarios_test), 'Missing scenarios_test in cache.');
scens = out.scenarios_test;
meta = out.meta;

% Get u0
if isfield(out,'u0') && ~isempty(out.u0)
    u0 = out.u0;
else
    u0 = build_safe_u0(scens, meta);
end

% Get params
if isfield(out,'params') && ~isempty(out.params)
    params = out.params;
elseif isfield(out,'params0')
    params = out.params0;
else
    params = struct();
end

S = min(n_scen, numel(scens));
sc_sub = scens(1:S);

fprintf('\n[Smoke] Evaluating %d test scenarios...\n', S);

% Call user's evaluator (preferred)
if exist('eval_objectives_CVaR','file') == 2
    try
        [f1,f2,f3,det] = eval_objectives_CVaR(u0, sc_sub, params);
        fprintf('[Smoke] eval_objectives_CVaR OK. f1=%.4g, f2=%.4g, f3=%.4g\n', f1, f2, f3);
        if exist('det','var')
            show_det_summary(det);
        end
    catch ME
        fprintf(2,'[Smoke] eval_objectives_CVaR FAILED: %s\n', ME.message);
        rethrow(ME);
    end
else
    error('eval_objectives_CVaR.m not found on path.');
end

fprintf('[Smoke] Done.\n\n');
end

function u0 = build_safe_u0(scens, meta)
% Build a conservative u0 compatible with eval_objectives_CVaR.
% Expected format: u0 is 2R-by-1, u0 = [u_ch (R); u_cp (R)].

sc = scens(1);
if isfield(sc,'P_EV_req')
    P_req = sc.P_EV_req;
elseif isfield(sc,'P_req_rt')
    P_req = sc.P_req_rt;
else
    error('Cannot find EV request field (P_EV_req or P_req_rt) in scenario.');
end
[R,~] = size(P_req);

% Take max across scenarios and time per zone
Pmax_z = zeros(R,1);
Wmax_z = zeros(R,1);
for s=1:numel(scens)
    sc = scens(s);
    if isfield(sc,'P_EV_req'); P = sc.P_EV_req; else; P = sc.P_req_rt; end
    Pmax_z = max(Pmax_z, max(P, [], 2));

    if isfield(sc,'lambda_req_rt')
        W = sc.lambda_req_rt;
        Wmax_z = max(Wmax_z, max(W, [], 2));
    end
end

u_ch = 1.10 * Pmax_z; % kW (per-zone cap)

if any(Wmax_z > 0)
    u_cp = 1.10 * Wmax_z; % workload units per slot (per-zone cap)
else
    u_cp = ones(R,1);
end

u0 = [u_ch(:); u_cp(:)];

% Store convention in meta if available (best-effort)
if isfield(meta,'u_format') %#ok<*ISFLD>
    % no-op
end
end

function show_det_summary(det)
% Best-effort summary
if isstruct(det)
    if isfield(det,'feasible_rate')
        fprintf('[Smoke] feasible_rate=%.3f\n', det.feasible_rate);
    end
    if isfield(det,'mean_cost')
        fprintf('[Smoke] mean_cost=%.4g\n', det.mean_cost);
    end
end
end
