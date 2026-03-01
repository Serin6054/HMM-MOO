function params = oracle_make_params(varargin)
%ORACLE_MAKE_PARAMS  Default params for oracle + scalarization.
%
% This project uses a simulation-based oracle:
%   - eval_objectives_CVaR implements paper-aligned (f1,f2,f3) and returns
%     detailed per-scenario traces in det.
%   - oracle_eval scalarizes (f1,f2,f3) into a scalar fitness Y(u), and can
%     return an infeasibility indicator flaginf(u)\in{0,1} with a large
%     deterministic penalty injected into Y(u).
%
% Name-value overrides:
%   'eval.<field>'        -> params.eval.<field>
%   'infeas.<field>'      -> params.infeas.<field>
%   'infeas.opf.<field>'  -> params.infeas.opf.<field>
%   otherwise             -> params.<field>

params = struct();

% ----- objective/risk knobs (paper-aligned; match eval_objectives_CVaR) -----
% CVaR confidence level
params.alpha    = 0.90;
% charging shortfall penalty κ_sf
params.kappa_sf = 0.0;
% composite loss weights: L = β_J J + β_el O_el + β_cmp O_cmp
params.beta_J   = 1.0;
params.beta_el  = 1.0;
params.beta_cmp = 1.0;
% numerical stabilizers / proxy electrical capacity construction
params.eps_F      = 1e-6;
params.cap_factor = 0.75;    

% ----- scalarization (paper) -----
% fitness = λ_el f1(u) + λ_cmp f2(u) + λ_R f3(u)
params.lambda_el  = 1.0;
params.lambda_cmp = 1.0;
params.lambda_R   = 1.0;

% ----- scenario protocol for optimization -----
params.eval = struct();
params.eval.mode       = "minibatch"; % "full" or "minibatch"
params.eval.B          = 30;
params.eval.K_resamp   = 1;
params.eval.seed       = 2025;

% ----- infeasibility handling (paper flaginf) -----
% flaginf is set to 1 when the network evaluation fails or violates limits
% beyond tolerance. For speed, the default uses a proxy based on O_el/O_cmp.
params.infeas = struct();
params.infeas.enable   = true;
params.infeas.mode     = "proxy";   % "proxy" or "opf"
params.infeas.penalty  = 1e9;       % deterministic penalty added to Y(u)

% proxy tolerances (trigger infeasibility when exceeded)
% O_el, O_cmp are defined per scenario in eval_objectives_CVaR.
params.infeas.tol_Oel  = 0.05;      % e.g., >5% overload proxy
params.infeas.tol_Ocmp = 0.05;

% OPF-based infeasibility (MATPOWER) for reporting (expensive)
params.infeas.opf = struct();
params.infeas.opf.case_path  = fullfile('data','case33bw.m');
params.infeas.opf.map_csv    = fullfile('data','zone_to_bus.csv');
params.infeas.opf.pf_load    = 0.95;   % assumed load power factor for added load
params.infeas.opf.Vmin       = 0.95;
params.infeas.opf.Vmax       = 1.05;
params.infeas.opf.tol_V      = 0.0;    % extra admissible tolerance
params.infeas.opf.tol_line   = 0.0;    % line loading tolerance (ratio)
params.infeas.opf.try_pf_fallback = true;
params.infeas.opf.verbose    = false;
% --- workload intensity scaling (to make f2 non-trivial) ---
if ~isfield(params,'workload_scale'), params.workload_scale = 1.0; end

% override
if mod(numel(varargin),2)~=0
    error('oracle_make_params expects name-value pairs.');
end
for i=1:2:numel(varargin)
    key = varargin{i};
    val = varargin{i+1};

    if startsWith(key,"eval.")
        sub = extractAfter(key,"eval.");
        params.eval.(sub) = val;
    elseif startsWith(key,"infeas.opf.")
        sub = extractAfter(key,"infeas.opf.");
        params.infeas.opf.(sub) = val;
    elseif startsWith(key,"infeas.")
        sub = extractAfter(key,"infeas.");
        params.infeas.(sub) = val;
    else
        params.(key) = val;
    end
end
end
