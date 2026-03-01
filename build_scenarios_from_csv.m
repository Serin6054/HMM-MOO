function scenarios = build_scenarios_from_csv(data_dir, varargin)
% BUILD_SCENARIOS_FROM_CSV  Build daily scenarios from CSV inputs (EV + Edge workloads).
%
%   scenarios = build_scenarios_from_csv(data_dir)
%   scenarios = build_scenarios_from_csv(data_dir, 'Name', Value, ...)
%
% INPUTS (kept unchanged; expected under data_dir):
%   volume.csv            : EV charging demand proxy by zone and hour
%   e_price.csv           : electricity price by zone and hour
%   s_price.csv           : service price (optional) by zone and hour
%   inf.csv               : zone info incl. charge_count
%   distance.csv          : zone distance matrix (optional; used for advanced models)
%   weather_central.csv   : weather series (optional; used for advanced models)
%
% OUTPUT:
%   scenarios : 1 x S struct array, each scenario is one day with fields:
%       .R, .T, .dt
%       .date                 datetime (day label)
%       .P_req_rt             [R x T] EV power request proxy (kW)
%       .lambda_req_rt        [R x T] compute workload arrival (units/h)
%       .Pmax                 [1 x R] charging capacity (kW)
%       .Fcap                 [1 x R] compute capacity (units/h)
%       .price_e, .price_s    [1 x T]
%       .price                [1 x T] used for cost (default = price_e)
%       .Pedge_idle/.Pedge_peak [1 x R] edge electrical power params (kW)
%       .Psys_cap             scalar electrical proxy capacity (kW)
%
% NOTE:
%   - This builder keeps the ORIGINAL input CSVs unchanged.
%   - Compute workload is GENERATED here (reproducible via seed) to be treated
%     as an exogenous scenario input, with a tunable correlation to EV demand.
%
% -------------------------------------------------------------------------

    %% ---- options ----
    opts = struct();
    opts.T_day  = 24;
    opts.dt     = 1.0;      % hour
    opts.seed   = 2025;

    % compute workload generation knobs
    opts.workload = struct();
    opts.workload.model      = "diurnal_corr";  % "diurnal_corr" | "linear_ev" (legacy)
    opts.workload.rho        = 0.6;             % correlation strength with EV demand in [0,1]
    opts.workload.kappa      = 1.0;             % overall workload scale
    opts.workload.base_level = 5.0;             % base arrival (units/h)
    opts.workload.amp_level  = 40.0;            % diurnal amplitude (units/h)
    opts.workload.noise_sigma= 0.15;            % lognormal multiplicative noise
    opts.workload.tail_p     = 0.05;            % probability of rare spike per (zone,hour)
    opts.workload.tail_mult  = 2.5;             % spike multiplier

    % edge power model knobs (kW per compute capacity unit)
    opts.edge = struct();
    opts.edge.Pidle_per_F = 0.002;  % kW per unit of Fcap  (=> ~0.2 kW/server if Fcap/100 servers)
    opts.edge.Ppeak_per_F = 0.005;  % kW per unit of Fcap

    % electrical proxy capacity (if you do not run OPF screening)
    opts.Psys_cap_factor = 1.0;     % Psys_cap = factor * sum(Pmax)

    % overrides via name-value
    if mod(numel(varargin),2)~=0
        error('build_scenarios_from_csv expects name-value pairs.');
    end
    for i=1:2:numel(varargin)
        k = varargin{i}; v = varargin{i+1};
        if ischar(k) || isstring(k)
            k = char(k);
            if startsWith(k,'workload.')
                sub = extractAfter(string(k),'workload.');
                opts.workload.(char(sub)) = v;
            elseif startsWith(k,'edge.')
                sub = extractAfter(string(k),'edge.');
                opts.edge.(char(sub)) = v;
            else
                opts.(k) = v;
            end
        end
    end

    rng(opts.seed, 'twister');

    %% ---- 1) read time series ----
    vol_tbl = readtable(fullfile(data_dir, 'volume.csv'));
    e_tbl   = readtable(fullfile(data_dir, 'e_price.csv'));
    s_tbl   = readtable(fullfile(data_dir, 's_price.csv'));

    % robust: try keep ALL rows; if not divisible by 24, fall back by dropping the first row
    vol_data = vol_tbl{:, 2:end};
    e_data   = e_tbl{:,   2:end};
    s_data   = s_tbl{:,   2:end};

    [T_total, R] = size(vol_data);

    if mod(T_total, opts.T_day) ~= 0
        % fallback: drop first row (some CSV exports include a dummy first line)
        vol_data = vol_tbl{2:end, 2:end};
        e_data   = e_tbl{2:end,   2:end};
        s_data   = s_tbl{2:end,   2:end};
        [T_total, R] = size(vol_data);
    end
    if mod(T_total, opts.T_day) ~= 0
        error('Time series length (%d) is not a multiple of %d. Please check your CSV.', T_total, opts.T_day);
    end

    n_days = T_total / opts.T_day;
    T_day  = opts.T_day;
    dt     = opts.dt;

    % parse timestamps (optional but recommended for calendar split)
    day_dates = NaT(n_days,1);
    try
        tstr = string(vol_tbl{:,1});
        if numel(tstr) >= T_total
            t_all = datetime(tstr(1:T_total), 'InputFormat','yyyy/M/d H:mm', 'Format','yyyy-MM-dd');
            for d = 1:n_days
                day_dates(d) = dateshift(t_all((d-1)*T_day+1), 'start', 'day');
            end
        end
    catch
        % keep NaT; split script will fall back to chronological 80/20
    end

    %% ---- 2) capacities from inf.csv ----
    % inf.csv: (>=10 x 6) [TAZID, lon, lat, charge_count, area, perimeter]
    inf_data = readmatrix(fullfile(data_dir, 'inf.csv'));
    TAZID      = inf_data(:,1);
    charge_cnt = inf_data(:,4);

    target_ids = 1:R; % use first R zones by id
    Pmax_vec   = zeros(1, numel(target_ids));
    Fcap_vec   = zeros(1, numel(target_ids));

    P_per_charger = 7;   % kW per charger (adjust if needed)
    F_per_charger = 50;  % compute capacity units per charger (proxy)

    zone_scale = ones(1, numel(target_ids));
    for r = 1:numel(target_ids)
        id = target_ids(r);
        idx = find(TAZID == id, 1, 'first');
        if isempty(idx)
            error('Cannot find TAZID = %d in inf.csv.', id);
        end
        cc = charge_cnt(idx);
        Pmax_vec(r) = max(cc,0) * P_per_charger;
        Fcap_vec(r) = max(cc,0) * F_per_charger;

        % zone scale used by compute workload generator (proxy for "activity")
        zone_scale(r) = max(cc,1);
    end
    zone_scale = zone_scale ./ mean(zone_scale); % normalize around 1

    %% ---- 3) edge electrical power parameters (kW) ----
    Pedge_idle = opts.edge.Pidle_per_F .* Fcap_vec;
    Pedge_peak = opts.edge.Ppeak_per_F .* Fcap_vec;
    Pedge_peak = max(Pedge_peak, Pedge_idle);

    % proxy electrical capacity (only used if OPF screening is not enabled)
    Psys_cap = max(opts.Psys_cap_factor * sum(Pmax_vec), 1e-3);

    %% ---- 4) allocate scenarios ----
    scen_template = struct( ...
        'R',             [], ...
        'T',             [], ...
        'dt',            [], ...
        'date',          [], ...
        'P_req_rt',      [], ...
        'lambda_req_rt', [], ...
        'Pmax',          [], ...
        'Fcap',          [], ...
        'price_e',       [], ...
        'price_s',       [], ...
        'price',         [], ...
        'Pedge_idle',    [], ...
        'Pedge_peak',    [], ...
        'Psys_cap',      [], ...
        'meta',          [] );

    scenarios = repmat(scen_template, n_days, 1);

    %% ---- 5) build per-day scenarios ----
    for d = 1:n_days
        idx_start = (d-1)*T_day + 1;
        idx_end   = d*T_day;

        P_day = vol_data(idx_start:idx_end, :);  % [T_day x R]
        e_day = e_data(idx_start:idx_end, :);
        s_day = s_data(idx_start:idx_end, :);

        P_req_rt = P_day.';   % [R x T_day]

        % compute workload arrival (units/h), generated (exogenous) here
        lambda_req_rt = generate_compute_workload(P_req_rt, zone_scale, opts.workload);

        price_e = mean(e_day, 2).';   % [1 x T_day]
        price_s = mean(s_day, 2).';   % [1 x T_day]
        price   = price_e;

        scen = scen_template;
        scen.R             = R;
        scen.T             = T_day;
        scen.dt            = dt;
        if ~all(isnat(day_dates))
            scen.date      = day_dates(d);
        else
            scen.date      = NaT;
        end
        scen.P_req_rt      = P_req_rt;
        scen.lambda_req_rt = lambda_req_rt;
        scen.Pmax          = Pmax_vec;
        scen.Fcap          = Fcap_vec;
        scen.price_e       = price_e;
        scen.price_s       = price_s;
        scen.price         = price;

        scen.Pedge_idle    = Pedge_idle;
        scen.Pedge_peak    = Pedge_peak;
        scen.Psys_cap      = Psys_cap;

        scen.meta = struct();
        scen.meta.workload = opts.workload;
        scen.meta.seed     = opts.seed;

        scenarios(d) = scen;
    end

    fprintf('Built %d daily scenarios: R=%d zones, T=%d slots/day.\n', n_days, R, T_day);
end


function lambda = generate_compute_workload(P_req_rt, zone_scale, wopts)
%GENERATE_COMPUTE_WORKLOAD  Generate compute workload arrivals (units/h).
% P_req_rt: [R x T] EV power request proxy (kW), used only for controllable correlation.
% zone_scale: [1 x R] relative activity weights (mean≈1).
%
% model:
%   "diurnal_corr": diurnal base + correlated EV component + heavy-tail spikes
%   "linear_ev"   : legacy a0 + a1 * P_req (kept for backward compatibility)

    [R,T] = size(P_req_rt);

    if ~isfield(wopts,'model'), wopts.model = "diurnal_corr"; end
    model = string(wopts.model);

    if model == "linear_ev"
        a0 = wopts.base_level;
        a1 = 0.2;
        lambda = a0 + a1 .* P_req_rt;
        lambda = max(lambda, 0);
        return;
    end

    % ---- diurnal base profile (peaks in evening) ----
    t = (1:T);
    % two-hump profile: morning + evening
    prof = 0.55 + 0.35*sin(2*pi*(t-8)/24) + 0.25*sin(2*pi*(t-18)/24);
    prof = max(prof, 0.05);
    prof = prof ./ mean(prof); % normalize mean to 1

    base = wopts.base_level + wopts.amp_level .* prof;   % [1 x T]
    base = reshape(base, 1, T);

    % ---- correlated EV component ----
    rho = min(max(wopts.rho, 0), 1);
    Pn  = P_req_rt;
    % normalize EV to [0,1] per-zone to avoid scale dominance
    Pmin = min(Pn, [], 2);
    Pmax = max(Pn, [], 2);
    denom = max(Pmax - Pmin, 1e-6);
    Pn = (Pn - Pmin) ./ denom;   % [R x T] in [0,1]

    corr_part = Pn .* mean(base);  % scale comparable to base mean

    % ---- combine ----
    lambda = (1-rho) .* (zone_scale(:) * base) + rho .* (zone_scale(:) .* corr_part);
    lambda = wopts.kappa .* lambda;

    % ---- multiplicative noise (lognormal) ----
    sig = max(wopts.noise_sigma, 0);
    if sig > 0
        epsn = exp(sig * randn(R,T) - 0.5*sig^2);  % mean≈1
        lambda = lambda .* epsn;
    end

    % ---- rare spikes (heavy tail) ----
    tp = min(max(wopts.tail_p, 0), 1);
    if tp > 0
        spike = (rand(R,T) < tp);
        lambda(spike) = lambda(spike) .* wopts.tail_mult;
    end

    lambda = max(lambda, 0);
end
