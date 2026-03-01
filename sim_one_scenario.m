function m = sim_one_scenario(u, scen, params)
%SIM_ONE_SCENARIO
% Within-cap simulation with optional two-stage recourse (backlog) and
% diurnal shaping for 2R controls (transition to true 2RT envelopes).
%
% u: [2R x 1] or [2RT x 1]
%   first  part = EV cap (kW)
%   second part = compute cap (work units per slot)
%
% scen fields:
%   P_req_rt        [R x T]  EV requested charging power (kW)
%   lambda_req_rt   [R x T]  compute workload arrivals (units/slot)
% optional:
%   Pedge_idle      [R x 1]  idle edge power (kW)
%   Pedge_peak      [R x 1]  peak edge power (kW)
%
% params fields (optional):
%   dt
%   switches.two_stage (0/1)
%   ev_shape (1xT), cp_shape (1xT) used when two_stage=1 AND u is 2R

    if nargin < 3, params = struct(); end
    if ~isfield(params,'dt'), params.dt = 1; end
    dt = params.dt;

    sw = struct();
    if isfield(params,'switches') && isstruct(params.switches)
        sw = params.switches;
    end
    two_stage = isfield(sw,'two_stage') && sw.two_stage==1;

    % --- requests ---
    if isfield(scen,'P_req_rt')
        P_req = scen.P_req_rt;
    elseif isfield(scen,'P_EV_req')
        P_req = scen.P_EV_req;
    else
        error('Scenario missing P_req_rt / P_EV_req.');
    end

    if isfield(scen,'lambda_req_rt')
        lam = scen.lambda_req_rt;
    elseif isfield(scen,'W_req_rt')
        lam = scen.W_req_rt;
    else
        error('Scenario missing lambda_req_rt / W_req_rt.');
    end

    [R,T] = size(P_req);
    assert(all(size(lam)==[R,T]), 'lambda size must match P_req size.');

    % --- parse u ---
    u = u(:);
    if numel(u) == 2*R
        u_ch = u(1:R);
        u_cp = u(R+1:2*R);

        % EXP-U-SCALE: auto-detect quota-vs-absolute control semantics.
        use_quota_mode = false;
        if isfield(scen,'Pmax') && isfield(scen,'Fcap')
            frac_in_range = mean([u_ch(:); u_cp(:)] >= -1e-9 & [u_ch(:); u_cp(:)] <= 1.5);
            use_quota_mode = (frac_in_range >= 0.8);
        end

        if use_quota_mode
            P_allow = max(u_ch,0) .* scen.Pmax(:);
            F_allow = max(u_cp,0) .* scen.Fcap(:);
        else
            P_allow = u_ch;
            F_allow = u_cp;
        end

        % default: constant over time
        P_allow_rt = repmat(P_allow,1,T);
        F_allow_rt = repmat(F_allow,1,T);
        
        % diurnal shaping for 2R -> 2RT (apply regardless of two_stage)
        if isfield(params,'ev_shape') && numel(params.ev_shape)==T
            sev = params.ev_shape(:)';        % 1xT
            P_allow_rt = bsxfun(@times, P_allow, sev);
        end
        if isfield(params,'cp_shape') && numel(params.cp_shape)==T
            scp = params.cp_shape(:)';        % 1xT
            F_allow_rt = bsxfun(@times, F_allow, scp);
        end

    elseif numel(u) == 2*R*T
        P_allow_rt = reshape(u(1:R*T), R, T);
        F_allow_rt = reshape(u(R*T+1:2*R*T), R, T);
        P_allow = mean(P_allow_rt,2);
        F_allow = mean(F_allow_rt,2);
    else
        error('Control vector length must be 2R or 2RT (R=%d,T=%d).', R, T);
    end

    % --- edge power params ---
    if isfield(scen,'Pedge_idle'), P_idle = scen.Pedge_idle(:); else, P_idle = zeros(R,1); end
    if isfield(scen,'Pedge_peak'), P_peak = scen.Pedge_peak(:); else, P_peak = P_idle; end
    if numel(P_idle)==1, P_idle = repmat(P_idle,R,1); end
    if numel(P_peak)==1, P_peak = repmat(P_peak,R,1); end

    % outputs
    P_EV_serv = zeros(R,T);
    W_serv    = zeros(R,T);

    if ~two_stage
        % --------- Single-stage: per-slot truncation ----------
        P_EV_serv = min(P_req, P_allow_rt);
        W_serv    = min(lam,   F_allow_rt);

        DeltaP_EV = max(P_req - P_EV_serv, 0);   % [R x T] kW
        DeltaW    = max(lam   - W_serv,    0);   % [R x T] units

    else
        % --------- Two-stage: backlog recourse ----------
        Qe = zeros(R,1);  % EV backlog energy (kWh)
        Qw = zeros(R,1);  % compute backlog (units)

        DeltaP_EV = zeros(R,T);  % penalize only end-of-day residual backlog
        DeltaW    = zeros(R,T);

        for t = 1:T
            % EV backlog in energy domain
            E_req = P_req(:,t) * dt;        % kWh
            E_cap = P_allow_rt(:,t) * dt;   % kWh
            E_serv = min(E_req + Qe, E_cap);
            Qe = (E_req + Qe) - E_serv;
            P_EV_serv(:,t) = E_serv / dt;

            % Compute backlog in units
            W_req = lam(:,t);
            W_cap = F_allow_rt(:,t);
            W_serv(:,t) = min(W_req + Qw, W_cap);
            Qw = (W_req + Qw) - W_serv(:,t);
        end

        % End-of-day residual (this is what gets penalized)
        DeltaP_EV(:,T) = Qe / dt;   % kW-equivalent residual
        DeltaW(:,T)    = Qw;        % units residual
    end

    DeltaE = DeltaP_EV * dt;  % kWh

    % Edge power based on utilization of compute cap
    util = W_serv ./ max(F_allow_rt, 1e-9);
    util(~isfinite(util)) = 0;
    util = min(max(util,0),1);
    P_edge = repmat(P_idle,1,T) + util .* repmat((P_peak-P_idle),1,T);

    % --- pack compat outputs ---
    m = struct();
    m.debug = struct();
    m.debug.P_EV_serv = P_EV_serv;
    m.debug.P_edge    = P_edge;
    m.debug.DeltaP_EV = DeltaP_EV;
    m.debug.DeltaW    = DeltaW;
    m.debug.DeltaE    = DeltaE;

    m.debug.P_allow    = P_allow(:)';     % [1 x R]
    m.debug.F_allow    = F_allow(:)';     % [1 x R]
    m.debug.P_allow_rt = P_allow_rt;      % [R x T]
    m.debug.F_allow_rt = F_allow_rt;      % [R x T]

    m.debug.P_EV_req       = P_req;
    m.debug.lambda_req_rt  = lam;

    % aliases       
    m.debug.P_rt     = P_EV_serv;
    m.debug.Pedge_rt = P_edge;

    m.debug.two_stage = two_stage;  
    m.debug.has_slack_ev = any(P_allow_rt(:) > P_req(:));
    m.debug.has_slack_cp = any(F_allow_rt(:) > lam(:));
end
