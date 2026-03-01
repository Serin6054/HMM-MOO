function out = oracle_eval(u, scenarios, params, omega_idx)
%ORACLE_EVAL  Paper-aligned evaluator wrapper (3 objectives + feasibility penalty).
%
%   out = oracle_eval(u, scenarios, params, omega_idx)
%
% Inputs
%   u         : 1 x (2R) quota vector [u_ch(1..R), u_cp(1..R)] in [0,1]
%   scenarios : scenario set (struct array or cell) as used by eval_objectives_CVaR
%   params    : parameter struct (must include lambda_el, lambda_cmp, lambda_R)
%   omega_idx : indices of scenarios to use (optional; default all)
%
% Outputs (key fields)
%   out.f1, out.f2, out.f3         : THREE objectives (DO NOT include infeas penalty)
%   out.fitness_base               : lambda_el*f1 + lambda_cmp*f2 + lambda_R*f3
%   out.fitness                    : fitness_base + infeas_penalty * infeas_rate
%   out.flaginf                    : 1 if infeas_rate > 0, else 0
%   out.infeas_rate                : mean(flaginf_s) over omega_idx
%   out.E_Oel, out.E_Ocmp          : expected overload proxies over omega_idx (if available)
%   out.det                        : details returned by eval_objectives_CVaR (if any)
%
% IMPORTANT:
%   - The infeasibility penalty must ONLY affect out.fitness (scalar Y(u)).
%   - Never overwrite out.f1/out.f2/out.f3 with large constants.

    t0 = tic;

    if nargin < 4 || isempty(omega_idx)
        % support struct array or cell array
        if iscell(scenarios)
            omega_idx = (1:numel(scenarios)).';
        else
            omega_idx = (1:numel(scenarios)).';
        end
    else
        omega_idx = omega_idx(:);
    end

    % ---- evaluate objectives (paper definition) ----
    det = struct();
    try
        % preferred signature
        [f1,f2,f3,det] = eval_objectives_CVaR(u, scenarios, params, omega_idx);
    catch
        % backward-compatible signature
        [f1,f2,f3,det] = eval_objectives_CVaR(u, scenarios, params);
    end

    % ---- scenario weights (if available) ----
    piw = [];
    if isstruct(det) && isfield(det,'piw') && ~isempty(det.piw)
        piw = det.piw(:);
    elseif isstruct(det) && isfield(det,'pi') && ~isempty(det.pi)
        piw = det.pi(:);
    end
    if isempty(piw)
        % equal weights over used scenarios
        piw = ones(numel(omega_idx),1) / max(numel(omega_idx),1);
    else
        % normalize
        s = sum(piw);
        if s <= 0 || ~isfinite(s)
            piw = ones(numel(piw),1) / max(numel(piw),1);
        else
            piw = piw / s;
        end
    end

    % ---- infeasibility bookkeeping (do NOT touch f1/f2/f3) ----
    flaginf_s = [];
    if isstruct(det) && isfield(det,'flaginf_s')
        flaginf_s = det.flaginf_s(:);
    elseif isstruct(det) && isfield(det,'flaginf')
        flaginf_s = det.flaginf(:);
    end
    if isempty(flaginf_s)
        infeas_rate = 0;
    else
        infeas_rate = mean(flaginf_s > 0);
    end
    flaginf = (infeas_rate > 0);

    % ---- overload proxies expectation (if available) ----
    E_Oel  = NaN;
    E_Ocmp = NaN;
    if isstruct(det) && isfield(det,'Oel_s') && ~isempty(det.Oel_s)
        v = det.Oel_s(:);
        E_Oel = sum(piw(1:numel(v)) .* v(1:numel(piw)));
    elseif isstruct(det) && isfield(det,'Oel') && ~isempty(det.Oel)
        v = det.Oel(:);
        E_Oel = sum(piw(1:numel(v)) .* v(1:numel(piw)));
    end

    if isstruct(det) && isfield(det,'Ocmp_s') && ~isempty(det.Ocmp_s)
        v = det.Ocmp_s(:);
        E_Ocmp = sum(piw(1:numel(v)) .* v(1:numel(piw)));
    elseif isstruct(det) && isfield(det,'Ocmp') && ~isempty(det.Ocmp)
        v = det.Ocmp(:);
        E_Ocmp = sum(piw(1:numel(v)) .* v(1:numel(piw)));
    end

    % ---- weights for scalarization ----
    lambda_el  = get_param(params, 'lambda_el',  1.0);
    lambda_cmp = get_param(params, 'lambda_cmp', 1.0);
    lambda_R   = get_param(params, 'lambda_R',   1.0);

    fitness_base = lambda_el * f1 + lambda_cmp * f2 + lambda_R * f3;

    % ---- infeasibility penalty applies ONLY to scalar fitness ----
    infeas_penalty = get_infeas_penalty(params);
    fitness = fitness_base + infeas_penalty * infeas_rate;

    % ---- pack outputs ----
    out = struct();
    out.f1 = f1;
    out.f2 = f2;
    out.f3 = f3;

    out.fitness_base = fitness_base;
    out.fitness      = fitness;

    out.flaginf      = double(flaginf);
    out.infeas_rate  = infeas_rate;

    out.E_Oel  = E_Oel;
    out.E_Ocmp = E_Ocmp;

    out.det = det;
    out.det.flaginf_s = flaginf_s;

    out.omega_idx = omega_idx;
    out.S_used    = numel(omega_idx);
    out.time_sec  = toc(t0);
end

% ========================= helpers =========================

function v = get_param(params, name, default)
    v = default;
    if isstruct(params) && isfield(params, name)
        tmp = params.(name);
        if isnumeric(tmp) && isscalar(tmp) && isfinite(tmp)
            v = tmp;
        end
    end
end

function p = get_infeas_penalty(params)
    p = 0;
    if ~isstruct(params)
        return;
    end
    % allow both params.infeas.penalty and params.infeas_penalty
    if isfield(params,'infeas') && isstruct(params.infeas)
        if isfield(params.infeas,'enable') && ~params.infeas.enable
            p = 0; return;
        end
        if isfield(params.infeas,'penalty') && isnumeric(params.infeas.penalty)
            p = params.infeas.penalty;
            return;
        end
    end
    if isfield(params,'infeas_penalty') && isnumeric(params.infeas_penalty)
        p = params.infeas_penalty;
    end
    if ~isscalar(p) || ~isfinite(p) || p < 0
        p = 0;
    end
end
