function [f1, f2, f3, details] = eval_objectives_CVaR(u, scenarios, params)
%EVAL_OBJECTIVES_CVAR  Paper-aligned objective components (3 terms).
%
%   [f1,f2,f3,details] = eval_objectives_CVaR(u, scenarios, params)
%
%   Objective definitions (paper):
%     - f1(u): expected electric-load energy  P_TOT(u,ω) aggregated over time
%     - f2(u): expected unmet computational workload ΔW(u,ω)
%     - f3(u): CVaR_α of composite loss L(u,ω) = β_J J + β_el O_el + β_cmp O_cmp
%
%   NOTE (IMPORTANT FIX):
%     This evaluator MUST pass `params` into sim_one_scenario(u, scen, params),
%     otherwise switches (two_stage/coupled/...) and diurnal shaping do not
%     affect f1/f2/f3. Previous versions calling sim_one_scenario(u,scen)
%     can make ablations indistinguishable.

    S = numel(scenarios);
    if S == 0
        error('eval_objectives_CVaR: scenarios is empty.');
    end
    if nargin < 3 || isempty(params), params = struct(); end

    u = u(:).';
    R = scenarios(1).R;
    if numel(u) ~= 2*R
        error('Control vector length must be 2R (R=%d).', R);
    end

    % ----- switches (defaults) -----
    sw = struct('two_stage',0,'cvar',1,'opf',0,'coupled',1,'ma_pso',0,'kalman',0,'va',0);
    if isfield(params,'switches') && isstruct(params.switches)
        fn = fieldnames(params.switches);
        for i=1:numel(fn)
            sw.(fn{i}) = params.switches.(fn{i});
        end
    end
    params.switches = sw;

    % ----- probabilities π_ω -----
    if isfield(params,'pi') && ~isempty(params.pi)
        piw = params.pi(:);
        if numel(piw) ~= S
            error('params.pi must have length S=%d.', S);
        end
        piw = piw / sum(piw);
    else
        piw = ones(S,1) / S;
    end

    % ----- defaults -----
    if ~isfield(params,'alpha')      || isempty(params.alpha),      params.alpha      = 0.9;   end
    if ~isfield(params,'kappa_sf')   || isempty(params.kappa_sf),   params.kappa_sf   = 0.0;   end
    if ~isfield(params,'beta_J')     || isempty(params.beta_J),     params.beta_J     = 1.0;   end
    if ~isfield(params,'beta_el')    || isempty(params.beta_el),    params.beta_el    = 1.0;   end
    if ~isfield(params,'beta_cmp')   || isempty(params.beta_cmp),   params.beta_cmp   = 1.0;   end
    if ~isfield(params,'eps_F')      || isempty(params.eps_F),      params.eps_F      = 1e-6;  end
    if ~isfield(params,'cap_factor') || isempty(params.cap_factor), params.cap_factor = 1.2;   end

    % ----- per-scenario scalars -----
    P_TOT = zeros(S,1);     % energy [kWh]
    DW    = zeros(S,1);     % unmet workload (unit of lambda_req_rt)
    J     = zeros(S,1);     % Yuan
    Oel   = zeros(S,1);     % overload proxy
    Ocmp  = zeros(S,1);     % overload proxy
    L     = zeros(S,1);     % composite loss

    % Coupling diagnostics (for reporting)
    Cbind  = NaN(S,1);      % "edge causes overload" rate
    Eshare = NaN(S,1);      % edge energy share

    for s = 1:S
        scen = scenarios(s);
        [P_base_z, P_cap_z] = local_get_base_and_cap(scen, params);

        % *** FIX: pass params into simulation (switches/shapes effective) ***
        m = sim_one_scenario(u, scen, params);

        % --- electrical totals (zone-time) ---
        % decoupled: base + EV only
        P_tot_ev   = bsxfun(@plus, P_base_z(:), m.debug.P_EV_serv);     % [R x T]
        % coupled: base + EV + edge
        P_tot_full = P_tot_ev + m.debug.P_edge;                        % [R x T]

        % choose which electrical coupling is "active"
        if sw.coupled == 1
            P_tot = P_tot_full;
        else
            P_tot = P_tot_ev;
        end

        % energy sum (kWh)
        P_TOT(s) = sum(P_tot(:)) * scen.dt;

        % overload proxy O_el
        EL = bsxfun(@rdivide, P_tot, P_cap_z(:));
        o_el = max(EL - 1, 0);
        Oel(s) = max(o_el(:));

        % --- computational unmet workload ---
        DW(s) = sum(m.debug.DeltaW(:));

        % overload proxy O_cmp (normalized unmet)
        F_allow = m.debug.F_allow;              % [1 x R]
        denom   = max(F_allow(:), 0) + params.eps_F;
        o_cmp   = bsxfun(@rdivide, m.debug.DeltaW, denom);  % [R x T]
        Ocmp(s) = max(o_cmp(:));

        % --- scenario-wise operating cost J(u,ω) ---
        price_e = [];
        price_s = [];
        if isfield(scen,'price_e'), price_e = scen.price_e; end
        if isempty(price_e) && isfield(scen,'price'), price_e = scen.price; end
        if isempty(price_e), price_e = zeros(1, size(m.debug.P_EV_serv,2)); end

        if isfield(scen,'price_s'), price_s = scen.price_s; end
        if isempty(price_s), price_s = zeros(size(price_e)); end

        price_e = price_e(:).';
        price_s = price_s(:).';

        % choose energy term consistent with coupling switch
        if sw.coupled == 1
            term_energy = (m.debug.P_EV_serv + m.debug.P_edge); % [R x T] kW
        else
            term_energy = (m.debug.P_EV_serv);                  % [R x T] kW (ignore edge-electric)
        end
        term_serv   = m.debug.P_EV_serv;                        % [R x T] kW
        term_short  = m.debug.DeltaP_EV;                        % [R x T] kW

        J(s) = sum( (repmat(price_e, R, 1) .* term_energy ...
                   - repmat(price_s, R, 1) .* term_serv ...
                   + params.kappa_sf .* term_short), 'all') * scen.dt;

        % --- coupling diagnostics (explainability) ---
        try
            EL_ev   = bsxfun(@rdivide, P_tot_ev,   P_cap_z(:));
            EL_full = bsxfun(@rdivide, P_tot_full, P_cap_z(:));
            hit = (EL_full > 1) & (EL_ev <= 1);         % overload ONLY due to edge coupling
            Cbind(s) = mean(hit(:));

            Eev   = sum(P_tot_ev(:))   * scen.dt;
            Efull = sum(P_tot_full(:)) * scen.dt;
            if Efull > 0
                Eshare(s) = (Efull - Eev) / Efull;      % fraction due to edge
            else
                Eshare(s) = 0;
            end
        catch
            % keep NaN
        end

        % --- composite loss + store ---
        L(s) = params.beta_J * J(s) + params.beta_el * Oel(s) + params.beta_cmp * Ocmp(s);
    end

    % ----- objective aggregation -----
    f1 = sum(piw .* P_TOT);
    f2 = sum(piw .* DW);

    % CVaR_α(L)
    [f3, eta] = local_weighted_cvar(L, piw, params.alpha);

    if nargout > 3
        details = struct();
        details.piw  = piw;  % 给 oracle_eval 用
        details.pi   = piw;  % 兼容其他脚本

        details.P_TOT = P_TOT;
        details.DW    = DW;
        details.J     = J;
        details.Oel   = Oel;
        details.Ocmp  = Ocmp;
        details.L     = L;
        details.eta   = eta;
        details.f1    = f1;
        details.f2    = f2;
        details.f3    = f3;

        % new: coupling explainability stats
        details.coupling_edge_overload_rate = mean(Cbind,'omitnan');
        details.coupling_edge_energy_share  = mean(Eshare,'omitnan');
        details.coupling_edge_overload_rate_s = Cbind;
        details.coupling_edge_energy_share_s  = Eshare;

        details.switches = sw;
    end
end

% ----------------------------- helpers -----------------------------

function [P_base_z, P_cap_z] = local_get_base_and_cap(scen, params)
% Returns 1xR vectors.
    R = scen.R;
    % --- P_base_z ---
    if isfield(params,'P_base_z') && ~isempty(params.P_base_z) && numel(params.P_base_z)==R
        P_base_z = params.P_base_z(:).';
    else
        P_base_z = local_try_load_base_from_case33(R);
    end

    % --- P_cap_z ---
    if isfield(params,'P_cap_z') && ~isempty(params.P_cap_z) && numel(params.P_cap_z)==R
        P_cap_z = params.P_cap_z(:).';
    else
        % proxy construction if no explicit capacity is provided
        P_cap_z = params.cap_factor * (P_base_z + scen.Pmax(:).');
        P_cap_z = max(P_cap_z, 1e-3);
    end
end

function P_base_z = local_try_load_base_from_case33(R)
% Best-effort: derive constant zone base load from data/case33bw.m + data/zone_to_bus.csv.
    persistent loaded Pbase_cached;
    if loaded
        if numel(Pbase_cached)==R
            P_base_z = Pbase_cached(:).';
        else
            P_base_z = zeros(1,R);
        end
        return;
    end

    P_base_z = zeros(1,R);
    try
        % resolve paths relative to repo root
        here = fileparts(mfilename('fullpath'));
        data_dir = fullfile(here, 'data');
        map_path = fullfile(data_dir, 'zone_to_bus.csv');
        case_path = fullfile(data_dir, 'case33bw.m');

        if exist(map_path,'file')~=2 || exist(case_path,'file')~=2
            loaded = true;
            Pbase_cached = P_base_z;
            return;
        end

        map = readmatrix(map_path);
        % map rows: [zone_id, bus_id]
        bus_ids = zeros(1,R);
        for z=1:R
            idx = find(map(:,1)==z, 1, 'first');
            if ~isempty(idx)
                bus_ids(z) = map(idx,2);
            else
                bus_ids(z) = 0;
            end
        end

        % ensure MATPOWER case file is on path
        if exist(data_dir,'dir')==7
            addpath(data_dir);
        end
        mpc = feval('case33bw');
        busno = mpc.bus(:,1);
        Pd    = mpc.bus(:,3); % kW in this case file

        for z=1:R
            if bus_ids(z) <= 0
                continue;
            end
            r = find(busno == bus_ids(z), 1, 'first');
            if ~isempty(r)
                P_base_z(z) = Pd(r);
            end
        end
    catch
        % keep zeros
    end

    loaded = true;
    Pbase_cached = P_base_z;
end

function [cvar, eta] = local_weighted_cvar(L, piw, alpha)
% Weighted CVaR using the standard representation in the paper.
    L = L(:);
    piw = piw(:);
    piw = piw / sum(piw);

    if alpha <= 0 || alpha >= 1
        error('alpha must be in (0,1).');
    end

    % weighted VaR (α-quantile)
    [Ls, idx] = sort(L, 'ascend');
    ps = piw(idx);
    cdf = cumsum(ps);
    k = find(cdf >= alpha, 1, 'first');
    if isempty(k)
        k = numel(Ls);
    end
    eta = Ls(k);

    tail = max(L - eta, 0);
    cvar = eta + (1/(1-alpha)) * sum(piw .* tail);
end
