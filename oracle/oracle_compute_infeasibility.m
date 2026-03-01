function [flaginf_s, meta] = oracle_compute_infeasibility(u, scenarios, det, params)
%ORACLE_COMPUTE_INFEASIBILITY  Compute scenario-wise infeasibility flags.
%
%   flaginf_s(s)=1 indicates scenario s is infeasible under plan u.
%
% Modes:
%   - params.infeas.mode == "proxy": fast proxy based on (O_el,O_cmp)
%   - params.infeas.mode == "opf"  : MATPOWER OPF/PF based check (expensive)
%
% The proxy mode is intended for optimization loops; OPF mode is intended
% for final reporting / interpretability studies.

S = numel(scenarios);
flaginf_s = false(S,1);

meta = struct();
meta.mode = "proxy";

if ~isfield(params,'infeas') || ~isfield(params.infeas,'enable') || ~params.infeas.enable
    meta.mode = "disabled";
    return;
end

mode = params.infeas.mode;
meta.mode = mode;

if strcmp(mode, "proxy")
    % ---- proxy based on overload metrics ----
    tolOel  = 0.0;
    tolOcmp = 0.0;
    if isfield(params.infeas,'tol_Oel'),  tolOel  = params.infeas.tol_Oel; end
    if isfield(params.infeas,'tol_Ocmp'), tolOcmp = params.infeas.tol_Ocmp; end

    if isfield(det,'Oel') && numel(det.Oel)==S
        flaginf_s = flaginf_s | (det.Oel(:) > tolOel);
    end
    if isfield(det,'Ocmp') && numel(det.Ocmp)==S
        flaginf_s = flaginf_s | (det.Ocmp(:) > tolOcmp);
    end

    % Also mark infeasible if per-scenario loss explodes / becomes non-finite
    if isfield(det,'L') && numel(det.L)==S
        flaginf_s = flaginf_s | ~isfinite(det.L(:));
    end

elseif strcmp(mode, "opf")
    % ---- OPF/PF based feasibility check (MATPOWER required) ----
    opf = params.infeas.opf;

    % load MATPOWER case only once
    persistent mpc_cache case_key M_cache M_key;

    if ~isfield(opf,'case_path') || isempty(opf.case_path)
        error('infeas.opf.case_path is required for OPF infeasibility mode.');
    end

    case_path = char(opf.case_path);
map_csv   = char(opf.map_csv);

% Resolve relative paths against the project root (..../code_new)
this_dir = fileparts(mfilename('fullpath'));  % .../code_new/oracle
root_dir = fileparts(this_dir);               % .../code_new

if exist(case_path,'file') ~= 2
    cand = fullfile(root_dir, case_path);
    if exist(cand,'file') == 2, case_path = cand; end
end
if exist(map_csv,'file') ~= 2
    cand = fullfile(root_dir, map_csv);
    if exist(cand,'file') == 2, map_csv = cand; end
end

key = string(case_path);
if isempty(case_key) || case_key ~= key
    % Load MATPOWER case
    if exist('loadcase','file') == 2
        mpc_cache = loadcase(case_path);
    else
        % Fallback: evaluate case function name (requires case folder on path)
        mpc_dir = fileparts(case_path);
        if ~isempty(mpc_dir) && exist(mpc_dir,'dir')
            addpath(mpc_dir);
        end
        mpc_cache = feval(strip_ext(case_path));
    end

    case_key  = key;
    M_cache   = [];
    M_key     = "";
end

    % build mapping M only once per (Nbus,R,map_csv)
    Nbus = size(mpc_cache.bus,1);
    R    = scenarios(1).R;
    mk = sprintf('%s|%d|%d', char(map_csv), Nbus, R);
    if isempty(M_key) || ~strcmp(M_key, mk)
        M_cache = build_M_from_zone_bus_csv(map_csv, Nbus, R);
        M_key   = mk;
    end

    for s = 1:S
        flaginf_s(s) = oracle_opf_check_day(u, scenarios(s), mpc_cache, M_cache, opf);
    end
else
    error('Unknown params.infeas.mode="%s". Use "proxy" or "opf".', mode);
end

meta.infeas_rate = mean(flaginf_s);
meta.flaginf = any(flaginf_s);
end

function n = strip_ext(p)
    [~, n] = fileparts(p);
end
