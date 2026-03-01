function is_infeas = oracle_opf_check_day(u, scen, mpc_base, M, opf)
%ORACLE_OPF_CHECK_DAY  Scenario-level infeasibility check via MATPOWER OPF/PF.
%
% is_infeas = oracle_opf_check_day(u, scen, mpc_base, M, opf)
%
% Returns is_infeas=1 if *any* time slot in the scenario:
%   - OPF (or PF fallback) fails to converge, OR
%   - voltage magnitude violates [Vmin,Vmax] beyond tol_V, OR
%   - any line loading ratio exceeds (1+tol_line).
%
% Intended usage:
%   - params.infeas.mode = "opf" in oracle_eval() for final reporting.
%
% Notes:
%   - Added loads are computed consistently with sim_one_scenario.
%   - This function is expensive (OPF/PF per slot) and not intended for
%     optimization inner loops.

R = scen.R; T = scen.T;
u = u(:).';
if numel(u) ~= 2*R
    error('u must be length 2R (R=%d).', R);
end

u_ch = u(1:R);
u_cp = u(R+1:2*R);

% ---------- served EV power per zone/time (kW) ----------
Pmax = scen.Pmax(:)';
P_allow = u_ch .* Pmax;
P_serv = min(scen.P_req_rt, repmat(P_allow(:), 1, T)); % [R x T]

% ---------- edge power per zone/time (kW) ----------
Pedge_idle = 0;
Pedge_peak = 0;
if isfield(scen,'Pedge_idle') && ~isempty(scen.Pedge_idle)
    Pedge_idle = scen.Pedge_idle;
end
if isfield(scen,'Pedge_peak') && ~isempty(scen.Pedge_peak)
    Pedge_peak = scen.Pedge_peak;
end
if isscalar(Pedge_idle), Pedge_idle = Pedge_idle * ones(1,R); end
if isscalar(Pedge_peak), Pedge_peak = Pedge_peak * ones(1,R); end
Pedge_idle = max(Pedge_idle, 0);
Pedge_peak = max(Pedge_peak, Pedge_idle);

Fcap = scen.Fcap(:)';
F_allow = max(u_cp .* Fcap, 1e-3);
rho = scen.lambda_req_rt ./ repmat(F_allow(:), 1, T); % [R x T]
rhoN = min(max(rho,0),1);

P_edge = repmat(u_cp(:),1,T) .* (...
    repmat(Pedge_idle(:),1,T) + ...
    (repmat(Pedge_peak(:)-Pedge_idle(:),1,T) .* rhoN));

P_zone = P_serv + P_edge; % [R x T]

% ---------- OPF config ----------
pf_load = 0.95;
if isfield(opf,'pf_load') && ~isempty(opf.pf_load)
    pf_load = opf.pf_load;
end
pf_load = min(max(pf_load, 0.01), 1.0);

Vmin = 0.95; Vmax = 1.05;
if isfield(opf,'Vmin'), Vmin = opf.Vmin; end
if isfield(opf,'Vmax'), Vmax = opf.Vmax; end

tol_V = 0.0; tol_line = 0.0;
if isfield(opf,'tol_V'), tol_V = opf.tol_V; end
if isfield(opf,'tol_line'), tol_line = opf.tol_line; end

try_pf = true;
if isfield(opf,'try_pf_fallback')
    try_pf = logical(opf.try_pf_fallback);
end

mpopt = mpoption('verbose',0,'out.all',0);

% load power factor for added load
% Q = P * tan(acos(pf))
tanphi = tan(acos(pf_load));

% ---------- loop slots ----------
for t = 1:T
    mpc = mpc_base;

    % additional load mapped to buses (MW)
    P_add_bus_MW = (M * P_zone(:,t)) / 1000;
    Q_add_bus_MW = P_add_bus_MW * tanphi;

    % add to existing demand
    mpc.bus(:,3) = mpc.bus(:,3) + P_add_bus_MW; % PD
    mpc.bus(:,4) = mpc.bus(:,4) + Q_add_bus_MW; % QD

    % try OPF; fallback to PF
    try
        res = runopf(mpc, mpopt);
        if ~isfield(res,'success') || ~res.success
            error('runopf not successful');
        end
    catch
        if ~try_pf
            is_infeas = true;
            return;
        end
        try
            res = runpf(mpc, mpopt);
            if ~isfield(res,'success') || ~res.success
                error('runpf not successful');
            end
        catch
            is_infeas = true;
            return;
        end
    end

    % voltage check
    Vm = res.bus(:,8);
    if any(Vm < (Vmin - tol_V)) || any(Vm > (Vmax + tol_V))
        is_infeas = true;
        return;
    end

    % line loading check (apparent power / rateA)
    rateA = res.branch(:,6);
    PF = res.branch(:,14);
    QF = res.branch(:,15);
    Sf = sqrt(PF.^2 + QF.^2);
    idx = rateA > 1e-6;
    ratio = abs(Sf(idx)) ./ rateA(idx);

    if any(ratio > (1 + tol_line))
        is_infeas = true;
        return;
    end
end

is_infeas = false;
end
