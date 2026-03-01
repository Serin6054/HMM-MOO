function out = planner_day_ahead_mappso_kf_va(scens_design, params, opts)
%PLANNER_DAY_AHEAD_MAPPSO_KF_VA Wrapper FUNCTION for legacy script-based planners.
%
% Goal:
%   Provide a FUNCTION entrypoint that solve_day_ahead_proposed can call.
%
% Default behavior:
%   - Runs your existing script: run_phase5_planner.m
%   - The script must assign one of these variables before it ends:
%       u, u_best, u_opt, u_DA, u_da, best_u
%   - Returns out.u as a column vector (2R or 2RT)
%
% Usage:
%   step3_run_main_results_minimal(...,'proposed_entrypoint','planner_day_ahead_mappso_kf_va')

if nargin < 3; opts = struct(); end
if nargin < 2 || isempty(params); params = struct(); end

% Provide common variable names the script may expect
scenarios_design = scens_design; %#ok<NASGU>
scenarios = scens_design; %#ok<NASGU>
params0 = params; %#ok<NASGU>
opts0 = opts; %#ok<NASGU>
params_in = params; %#ok<NASGU>
opts_in = opts; %#ok<NASGU>

% ---------------- RUN YOUR PLANNER SCRIPT ----------------
% If your actual entry script is different, change the file name here.
script_path = which('run_phase5_planner.m');
old_pwd = pwd;
try
    cd(fileparts(script_path));
    % Make switches visible to the script
    params_in = params;
    opts_in   = opts;     %#ok<NASGU>
    assignin('base','params_in',params_in);
    assignin('base','opts_in',opts_in);
    run(script_path);
catch ME
    cd(old_pwd);
    rethrow(ME);
end
cd(old_pwd);
% ---------------------------------------------------------

% Extract u from workspace
cands = {'u','u_best','u_opt','u_DA','u_da','best_u','u_sol','u_star'};
u = [];
for i=1:numel(cands)
    if exist(cands{i},'var')
        u = eval(cands{i});
        break;
    end
end

if isempty(u)
    w = whos;
    names = string({w.name});
    error('planner_day_ahead_mappso_kf_va:NoU', ...
        'run_phase5_planner.m did not assign u. Add at end of the script:\n  u = <2R or 2RT vector>;\nWorkspace has: %s', ...
        strjoin(names(1:min(end,30)), ', '));
end

out = struct();
out.u = u(:);
out.note = 'Wrapper executed run_phase5_planner.m and extracted u from workspace.';
end
