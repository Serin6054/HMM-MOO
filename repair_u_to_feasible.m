function u2 = repair_u_to_feasible(u, scenarios, params, max_iter, step_cp)
%REPAIR_U_TO_FEASIBLE  Simple feasibility repair for quota vector u.
%
%   u2 = repair_u_to_feasible(u, scenarios, params, max_iter, step_cp)
%
% Heuristic:
%   1) Increase compute quotas u_cp to reduce compute shortfall/overload.
%   2) If still infeasible after u_cp saturates, slightly reduce charging quotas u_ch.
%
% This is only applied as a *post-processing* step before final evaluation
% (design/test), not inside the optimization loop.
%
% Notes:
%   - oracle_eval is expected to return fields: .flaginf and/or .infeas_rate.

if nargin < 4 || isempty(max_iter), max_iter = 30; end
if nargin < 5 || isempty(step_cp),  step_cp  = 0.02; end

u2 = u(:).';
dim = numel(u2);
if mod(dim,2) ~= 0
    error('u must have even length: [u_ch(1..R), u_cp(1..R)].');
end
R = dim/2;

step_ch = 0.01;

idx = (1:numel(scenarios)).';

for it = 1:max_iter
    out = oracle_eval(u2, scenarios, params, idx);

    infeas_rate = 0;
    if isfield(out,'infeas_rate'), infeas_rate = out.infeas_rate; end
    flaginf = 0;
    if isfield(out,'flaginf'), flaginf = out.flaginf; end

    if (flaginf==0) && (infeas_rate==0)
        return;
    end

    % 1) Raise compute quotas first
    old_cp = u2(R+1:end);
    u2(R+1:end) = min(1, u2(R+1:end) + step_cp);

    % If compute already saturated, start reducing charging a bit
    if all(u2(R+1:end) >= 1 - 1e-12) && all(abs(u2(R+1:end)-old_cp) < 1e-12)
        u2(1:R) = max(0, u2(1:R) - step_ch);
    end
end
end
