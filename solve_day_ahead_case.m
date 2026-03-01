function u = solve_day_ahead_case(case_id, scens_design, params)
%SOLVE_DAY_AHEAD_CASE Unified entry for Table-3 style ablation cases.
%
% The returned u must be compatible with eval_objectives_CVaR.
% Current evaluator contract:
%   length(u) == 2R, u = [u_ch (R); u_cp (R)]
%
% By default:
%   - C6-C8 will call solve_day_ahead_proposed if present (MA/KF/VA enabled)
%   - otherwise fall back to solve_day_ahead_fixed
%
% You can pass an external entrypoint (function wrapper) via:
%   params.proposed_entrypoint = 'planner_day_ahead_mappso_kf_va';
% Optional opts for proposed:
%   params.proposed_opts = struct(...);

if nargin < 3 || isempty(params); params = struct(); end

sw = get_case_switches(case_id);
params.switches = sw;

use_proposed = sw.ma_pso || sw.kalman || sw.va;

if use_proposed && exist('solve_day_ahead_proposed','file') == 2
    opts = struct();
    if isfield(params,'proposed_opts') && isstruct(params.proposed_opts)
        opts = params.proposed_opts;
    end
    u = solve_day_ahead_proposed(scens_design, params, opts);
else
    u = solve_day_ahead_fixed(scens_design, params, sw);
end
end
