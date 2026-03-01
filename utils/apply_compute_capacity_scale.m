function [scenarios2, params2, info] = apply_compute_capacity_scale(scenarios, params, kappaF, R, opts)
%APPLY_COMPUTE_CAPACITY_SCALE  Scale compute capacity fields (κ_F) robustly.
%
% This wrapper is kept for backward compatibility with older scripts that
% call utils/apply_compute_capacity_scale.m. The main scaling logic lives in
% the root-level apply_compute_capacity_scale.m (robust path-based scaler).
%
% Usage (compatible):
%   [scenarios2, params2, info] = apply_compute_capacity_scale(scenarios, params, kappaF, R)
%   [scenarios2, params2, info] = apply_compute_capacity_scale(scenarios, params, kappaF, R, opts)
%
% In this codebase, compute capacity is stored in scenarios as:
%   scenarios(s).Fcap   (1 x R)
%
% -------------------------------------------------------------------------

    if nargin < 5, opts = struct(); end

    % Prefer scaling in scenarios (oracle uses scenarios.Fcap).
    try
        [scenarios2, info] = scale_scenarios_Fcap(scenarios, kappaF);
    catch ME
        warning('apply_compute_capacity_scale(utils): scaling failed: %s', ME.message);
        scenarios2 = scenarios;
        info = struct('kappaF',kappaF,'scaled_scenario_fields',{{}},'scaled_param_fields',{{}},'details',struct());
    end

    % params currently do not store per-zone F (kept unchanged)
    params2 = params;

    %#ok<NASGU>
    R = R; opts = opts;
end

function [scenarios2, info] = scale_scenarios_Fcap(scenarios, kappaF)
    scenarios2 = scenarios;
    info = struct();
    info.kappaF = kappaF;
    info.scaled_param_fields = {};
    info.scaled_scenario_fields = {};
    info.details = struct();

    for s = 1:numel(scenarios2)
        if isfield(scenarios2(s),'Fcap') && isnumeric(scenarios2(s).Fcap)
            scenarios2(s).Fcap = kappaF .* scenarios2(s).Fcap;
            info.scaled_scenario_fields = union(info.scaled_scenario_fields, {'Fcap'});
        end
        % common aliases
        if isfield(scenarios2(s),'F') && isnumeric(scenarios2(s).F)
            scenarios2(s).F = kappaF .* scenarios2(s).F;
            info.scaled_scenario_fields = union(info.scaled_scenario_fields, {'F'});
        end
    end
end
