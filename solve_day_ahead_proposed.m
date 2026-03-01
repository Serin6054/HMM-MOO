function [u, info] = solve_day_ahead_proposed(scens_design, params, varargin)
%SOLVE_DAY_AHEAD_PROPOSED Day-ahead envelope planner (hook point for MA-PSO+KF+VA).
%
% Evaluator constraint (current project state):
%   eval_objectives_CVaR expects length(u) == 2R (time-invariant per-zone caps)
%   u = [u_ch (R); u_cp (R)]
%
% This function is written to be:
%   (i) immediately runnable (fallback heuristic), and
%   (ii) easy to connect to your existing MA-PSO+Kalman+VA solver via a FUNCTION entrypoint.
%
% Recommended integration path:
%   1) Create a function (NOT a script), e.g. planner_day_ahead_mappso_kf_va.m
%   2) Set: params.proposed_entrypoint = 'planner_day_ahead_mappso_kf_va'
%   3) Ensure the function returns:
%        - either a 2R vector u
%        - or a struct with field .u
%      (2RT is also accepted and will be collapsed to 2R).
%
% Safety:
%   If the external entrypoint fails (missing, script, runtime error), we
%   DO NOT throw; we fall back to a quantile envelope so experiments can run.
%
% Outputs:
%   u    : 2R-by-1 control vector
%   info : struct describing how u is produced

opts = struct();
if ~isempty(varargin)
    if isstruct(varargin{1}); opts = varargin{1}; end
end
if nargin < 2 || isempty(params); params = struct(); end

% --- switches / alpha ---
sw = struct('cvar',true,'coupled',true,'opf',false,'two_stage',true,'ma_pso',true,'kalman',true,'va',true);
if isfield(params,'switches') && isstruct(params.switches)
    fns = fieldnames(params.switches);
    for k=1:numel(fns)
        sw.(fns{k}) = params.switches.(fns{k});
    end
end

alpha = 0.90;
if isfield(params,'alpha') && isnumeric(params.alpha)
    alpha = params.alpha;
elseif isfield(params,'risk') && isstruct(params.risk) && isfield(params.risk,'alpha')
    alpha = params.risk.alpha;
end
q = 0.50;
if sw.cvar; q = alpha; end

% --- external entrypoint (FUNCTION strongly preferred) ---
entry = '';
if isfield(params,'proposed_entrypoint')
    entry = char(string(params.proposed_entrypoint));
elseif isfield(opts,'entrypoint')
    entry = char(string(opts.entrypoint));
end

info = struct();

% Try explicit entrypoint first
if ~isempty(strtrim(entry))
    [u_try, info_try, ok] = try_external_entrypoint(entry, scens_design, params, opts);
    if ok
        u = ensure_2R(u_try, scens_design, params);
        info = info_try;
        info.mode = 'external';
        info.entrypoint = entry;
        return;
    else
        info.external_error = info_try.external_error;
        info.external_error_id = info_try.external_error_id;
    end
end

% Auto-discovery: ONLY function files (avoid accidentally running big scripts)
known = {
    'planner_day_ahead_mappso_kf_va'
    'planner_day_ahead_mappso'
    'run_day_ahead_mappso_kf_va'
    'day_ahead_planner'
    'mappso_day_ahead'
};
for i=1:numel(known)
    if exist(known{i},'file') == 2 && is_function_mfile(known{i})
        [u_try, info_try, ok] = try_external_entrypoint(known{i}, scens_design, params, opts);
        if ok
            u = ensure_2R(u_try, scens_design, params);
            info = info_try;
            info.mode = 'external_auto';
            info.entrypoint = known{i};
            return;
        end
    end
end

% --- fallback heuristic (always runnable) ---
[u, info_h] = quantile_envelope(scens_design, q, sw);
info = info_h;
info.mode = 'heuristic_quantile';
info.q = q;
info.alpha = alpha;
info.switches = sw;

% Surface any external error as a hint, but do not fail.
if isfield(info,'external_error') && ~isempty(info.external_error)
    info.note = 'External entrypoint failed; used heuristic fallback.';
end
end

% ================= helpers =================

function [u, info, ok] = try_external_entrypoint(name, scens, params, opts)
info = struct(); ok = false; u = [];
try
    if exist(name,'file') ~= 2
        error('ExternalEntrypoint:NotFound','Entrypoint not found: %s', name);
    end

    if is_function_mfile(name)
        out = feval(name, scens, params, opts);
        if isstruct(out)
            if isfield(out,'u'); u = out.u; else; error('ExternalEntrypoint:BadReturn','%s returned struct without field .u', name); end
            info = out;
        else
            u = out;
        end
        ok = true;
        return;
    end

    % If user explicitly points to a script, we support it in a controlled way:
    out = run_script_entrypoint(name, scens, params, opts);
    if isstruct(out); u = out.u; info = out; else; u = out; end
    ok = true;
catch ME
    info.external_error = ME.message;
    info.external_error_id = ME.identifier;
    ok = false;
end
end

function out = run_script_entrypoint(script_name, scens, params, opts)
%RUN_SCRIPT_ENTRYPOINT Run a script entrypoint and extract u from workspace.
%
% NOTE: scripts are NOT ideal (hard to reproduce). Prefer making a function.
% Minimal change needed:
%   Ensure the script assigns one of: u, u_best, u_opt, u_DA, u_da, best_u

scenarios_design = scens; %#ok<NASGU>
scenarios = scens; %#ok<NASGU>
params_in = params; %#ok<NASGU>
opts_in = opts; %#ok<NASGU>
params0 = params; %#ok<NASGU>
opts0 = opts; %#ok<NASGU>

script_path = which(script_name);
if isempty(script_path)
    script_path = script_name;
end
run(script_path);

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
    error('ExternalEntrypoint:ScriptNoU', ...
        'Script %s did not assign u. Add at end: u = <2R or 2RT vector>;\nWorkspace has: %s', ...
        script_name, strjoin(names(1:min(end,30)), ', '));
end
out = struct('u', u, 'note', 'u extracted from script workspace');
end

function tf = is_function_mfile(name)
% Determine whether an m-file is a function (first non-comment line starts with 'function')
tf = false;
p = which(name);
if isempty(p); return; end
fid = fopen(p,'r');
if fid < 0; return; end
cleanup = onCleanup(@() fclose(fid));

while true
    ln = fgetl(fid);
    if ~ischar(ln); break; end
    s = strtrim(ln);
    if isempty(s); continue; end
    if startsWith(s, '%'); continue; end
    tf = startsWith(lower(s), 'function');
    break;
end
end

function u2 = ensure_2R(u, scens_design, params)
% Accept 2R or 2RT. Convert 2RT -> 2R by collapsing over time.
% Default collapse: mean; set params.collapse_2rt = 'max'|'mean'|'p90'
sc0 = scens_design(1);
[P, ~] = get_req_fields(sc0);
[R, T] = size(P);

method = 'mean';
if isfield(params,'collapse_2rt')
    method = char(string(params.collapse_2rt));
end

u = u(:);
if numel(u) == 2*R
    u2 = u;
    return;
end

if numel(u) == 2*R*T
    u_ch_ts = reshape(u(1:R*T), [R, T]);
    u_cp_ts = reshape(u(R*T+1:end), [R, T]);

    switch lower(method)
        case 'max'
            u_ch = max(u_ch_ts,[],2); u_cp = max(u_cp_ts,[],2);
        case 'p90'
            u_ch = quantile(u_ch_ts', 0.90)'; u_cp = quantile(u_cp_ts', 0.90)';
        otherwise
            u_ch = mean(u_ch_ts,2); u_cp = mean(u_cp_ts,2);
    end
    u2 = [u_ch(:); u_cp(:)];
    return;
end

error('Proposed solver returned u with length %d; expected 2R=%d or 2RT=%d.', numel(u), 2*R, 2*R*T);
end

function [u, info] = quantile_envelope(scens, q, sw)
% Quantile-based time-invariant caps per zone.
sc0 = scens(1);
[P0, W0] = get_req_fields(sc0);
[R, T] = size(P0);
S = numel(scens);

P_stack = zeros(R, T*S);
W_stack = zeros(R, T*S);
Pcap = inf(R,1);
Fcap = inf(R,1);

for s=1:S
    [P, W] = get_req_fields(scens(s));
    P_stack(:, (s-1)*T+1:s*T) = P;
    W_stack(:, (s-1)*T+1:s*T) = W;

    if isfield(scens(s),'P_cap')
        Pcap = min(Pcap, scens(s).P_cap(:));
    elseif isfield(scens(s),'Pmax_z')
        Pcap = min(Pcap, scens(s).Pmax_z(:));
    end
    if isfield(scens(s),'Fcap')
        Fcap = min(Fcap, scens(s).Fcap(:));
    elseif isfield(scens(s),'F_cap')
        Fcap = min(Fcap, scens(s).F_cap(:));
    end
end

u_ch = quantile(P_stack', q)';
u_cp = quantile(W_stack', q)';

marg = 1.05;
u_ch = marg * u_ch;
u_cp = marg * u_cp;

u_ch = min(u_ch, Pcap);
u_cp = min(u_cp, Fcap);

if sw.coupled
    sc = sc0;
    if isfield(sc,'Pedge_idle') && isfield(sc,'Pedge_peak') && isfield(sc,'Fcap')
        dP_per_unit = (sc.Pedge_peak(:) - sc.Pedge_idle(:)) ./ max(sc.Fcap(:), 1e-6);
        if isfield(sc,'P_total_cap')
            u_cp = min(u_cp, max((sc.P_total_cap(:) - u_ch - sc.Pedge_idle(:))./max(dP_per_unit,1e-6), 0));
        end
    end
end

u = [u_ch(:); u_cp(:)];
info = struct('u_ch',u_ch,'u_cp',u_cp,'R',R,'T',T);
end

function [P, W] = get_req_fields(sc)
if isfield(sc,'P_EV_req')
    P = sc.P_EV_req;
elseif isfield(sc,'P_req_rt')
    P = sc.P_req_rt;
else
    error('Scenario missing EV request power field (P_EV_req or P_req_rt).');
end

if isfield(sc,'lambda_req_rt')
    W = sc.lambda_req_rt;
elseif isfield(sc,'W_req_rt')
    W = sc.W_req_rt;
else
    W = zeros(size(P));
end
end
