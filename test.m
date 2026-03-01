% test_f123_coupling.m
% Direct-run script to test coupling among f1(), f2(), f3() in the paper
% by numerical cross-sensitivity (finite-difference Jacobian) + sample correlations.
%
% Usage:
%   >> test_f123_coupling
%
% Modes:
%   cfg.mode = "synthetic" (default): self-contained evaluator consistent with the paper formulas
%   cfg.mode = "project"            : call your own evaluator eval_f123_project(u)
%
% Coupling criterion used here:
%   Objectives are considered "coupled" if they show non-negligible sensitivity to BOTH
%   u_ch group and u_cp group (or if off-diagonal sensitivities are non-negligible).
%
% Note:
%   Because min/max operators can create flat regions, this script averages sensitivities
%   over multiple random points to avoid false "no coupling" conclusions.

clear; clc; close all;
rng(1);

%% -------------------- Configuration --------------------
cfg.mode = "synthetic";   % "synthetic" or "project"

% If synthetic:
cfg.Z = 10;               % number of zones
cfg.T = 96;               % time slots
cfg.W = 60;               % number of scenarios |Omega|
cfg.dt = 1;               % slot length (can be 0.25 if you use 15-min)
cfg.alpha = 0.90;         % CVaR confidence level alpha in (0,1)
cfg.kappa_sf = 2.0;       % penalty coefficient for EV shortfall
cfg.betaJ = 1.0;          % scaling weights in composite loss L
cfg.beta_el = 10.0;
cfg.beta_cmp = 5.0;
cfg.epsF = 1e-6;          % small constant for compute ratios

% Numerical test controls
cfg.M_jac = 25;           % number of random points for Jacobian averaging
cfg.h = 1e-4;             % finite-difference step
cfg.N_corr = 800;         % number of random samples for correlation check

% Thresholds (relative)
cfg.rel_tol = 1e-4;       % relative threshold vs max sensitivity magnitude

%% -------------------- Get evaluator --------------------
switch cfg.mode
    case "synthetic"
        prob = make_synthetic_problem(cfg);
        evalf = @(u) eval_f123_synthetic(u, prob);
    case "project"
        % You must implement eval_f123_project(u) in your MATLAB path.
        % It must return a 3x1 vector [f1; f2; f3].
        if exist('eval_f123_project', 'file') ~= 2
            error(['cfg.mode="project" requires a function eval_f123_project(u) ', ...
                   'that returns [f1; f2; f3].']);
        end
        prob.Z = []; %#ok<STRNU>
        evalf = @(u) eval_f123_project(u);
    otherwise
        error('Unknown cfg.mode.');
end

fprintf('=== Coupling test for f1,f2,f3 | mode=%s ===\n', cfg.mode);

%% -------------------- 1) Jacobian-based cross-sensitivity --------------------
% u = [u_ch(1..Z), u_cp(1..Z)]' in [0,1]^(2Z)
if cfg.mode == "synthetic"
    Z = prob.Z;
else
    % If project mode, you can set Z manually here if needed for grouping
    % (or infer from your system).
    Z = cfg.Z;  % fallback; adjust if your Z differs
end

n = 2*Z;
J_abs_acc = zeros(3, n, cfg.M_jac);

for m = 1:cfg.M_jac
    u = rand(n,1);                 % random point in [0,1]
    J = fd_jacobian(evalf, u, cfg.h);
    J_abs_acc(:,:,m) = abs(J);
end

J_abs_mean = mean(J_abs_acc, 3);   % average absolute Jacobian over points

idx_ch = 1:Z;
idx_cp = (Z+1):(2*Z);

S_ch = mean(J_abs_mean(:, idx_ch), 2);  % mean |df/d u_ch|
S_cp = mean(J_abs_mean(:, idx_cp), 2);  % mean |df/d u_cp|

S_max = max([S_ch; S_cp]);
tol = cfg.rel_tol * max(S_max, eps);

fprintf('\n[1] Mean absolute sensitivity (averaged over %d random points)\n', cfg.M_jac);
fprintf('    Each row is fi, columns are groups {u_ch, u_cp}\n');
disp(array2table([S_ch, S_cp], ...
    'VariableNames', {'mean|df/du_ch|','mean|df/du_cp|'}, ...
    'RowNames', {'f1','f2','f3'}));

coupled_to_ch = S_ch > tol;
coupled_to_cp = S_cp > tol;

fprintf('    Threshold tol = %.3e (relative %.1e of max sensitivity)\n', tol, cfg.rel_tol);
fprintf('    Coupling flags (1=yes, 0=no):\n');
disp(array2table([coupled_to_ch, coupled_to_cp], ...
    'VariableNames', {'depends_on_u_ch','depends_on_u_cp'}, ...
    'RowNames', {'f1','f2','f3'}));

% Simple "objective coupling" summary:
% - If an objective depends on both groups => strong cross-coupling across decision groups.
fprintf('    Interpretation:\n');
for i = 1:3
    if coupled_to_ch(i) && coupled_to_cp(i)
        fprintf('      - f%d shows cross-coupling (sensitive to BOTH u_ch and u_cp).\n', i);
    elseif coupled_to_ch(i) && ~coupled_to_cp(i)
        fprintf('      - f%d depends mainly on u_ch (weak/none on u_cp).\n', i);
    elseif ~coupled_to_ch(i) && coupled_to_cp(i)
        fprintf('      - f%d depends mainly on u_cp (weak/none on u_ch).\n', i);
    else
        fprintf('      - f%d appears insensitive to both groups at tested points (check flat regions / infeasibility / scaling).\n', i);
    end
end

%% Plot: group sensitivities
figure('Name','Group sensitivities');
bar([S_ch, S_cp]);
grid on;
set(gca,'XTickLabel',{'f1','f2','f3'});
legend({'u\_ch group','u\_cp group'}, 'Location','best');
ylabel('Mean |partial derivative|');
title('Cross-sensitivity of objectives to quota groups');

%% -------------------- 2) Sampling-based objective correlation --------------------
% Correlation among (f1,f2,f3) across random u does not prove coupling,
% but it reveals trade-offs / co-movement induced by shared structure/constraints.
F = zeros(cfg.N_corr, 3);
for k = 1:cfg.N_corr
    u = rand(n,1);
    f = evalf(u);
    F(k,:) = f(:).';
end

C = corrcoef(F);  % Pearson correlation
fprintf('\n[2] Correlation matrix among objectives over %d random samples:\n', cfg.N_corr);
disp(array2table(C, 'VariableNames', {'f1','f2','f3'}, 'RowNames', {'f1','f2','f3'}));

figure('Name','Objective correlations');
imagesc(C);
axis equal tight;
colorbar;
set(gca,'XTick',1:3,'XTickLabel',{'f1','f2','f3'}, ...
        'YTick',1:3,'YTickLabel',{'f1','f2','f3'});
title('corr(f1,f2,f3) over random quota samples');

%% -------------------- 3) Quick 1D sweeps (visual cross-coupling sanity check) --------------------
% Sweep u_cp scale while holding u_ch fixed; and vice versa.
u0 = 0.5*ones(n,1);

gridv = linspace(0,1,31);
F_sweep_cp = zeros(numel(gridv),3);
F_sweep_ch = zeros(numel(gridv),3);

% Sweep computing quotas: u_cp = s, u_ch fixed
for i = 1:numel(gridv)
    u = u0;
    u(idx_cp) = gridv(i);
    F_sweep_cp(i,:) = evalf(u).';
end

% Sweep charging quotas: u_ch = s, u_cp fixed
for i = 1:numel(gridv)
    u = u0;
    u(idx_ch) = gridv(i);
    F_sweep_ch(i,:) = evalf(u).';
end

figure('Name','1D sweeps');
subplot(2,1,1);
plot(gridv, F_sweep_cp(:,1), '-', gridv, F_sweep_cp(:,2), '-', gridv, F_sweep_cp(:,3), '-');
grid on;
xlabel('s (set all u\_cp = s)');
ylabel('Objective value');
legend({'f1','f2','f3'}, 'Location','best');
title('Sweep computing quotas (u\_ch fixed)');

subplot(2,1,2);
plot(gridv, F_sweep_ch(:,1), '-', gridv, F_sweep_ch(:,2), '-', gridv, F_sweep_ch(:,3), '-');
grid on;
xlabel('s (set all u\_ch = s)');
ylabel('Objective value');
legend({'f1','f2','f3'}, 'Location','best');
title('Sweep charging quotas (u\_cp fixed)');

fprintf('\nDone.\n');

%% ==================== Local functions ====================

function prob = make_synthetic_problem(cfg)
% Build a self-contained minimal instance consistent with the paper structure.
% prob stores arrays with dimensions:
%   Pbase(z,t,w), PEVreq(z,t,w), Wdem(z,t,w), lambda_e(z,t,w), lambda_s(z,t,w)
Z = cfg.Z; T = cfg.T; W = cfg.W;

prob.Z = Z; prob.T = T; prob.W = W;
prob.dt = cfg.dt;
prob.alpha = cfg.alpha;
prob.kappa_sf = cfg.kappa_sf;
prob.betaJ = cfg.betaJ;
prob.beta_el = cfg.beta_el;
prob.beta_cmp = cfg.beta_cmp;
prob.epsF = cfg.epsF;

% scenario probabilities (normalized)
piw = rand(W,1);
piw = piw / sum(piw);
prob.piw = piw;

% capacities per zone
prob.Pmax = 20 + 10*rand(Z,1);      % installed charging capacity
prob.Pcap = 25 + 10*rand(Z,1);      % electrical hosting capacity
prob.Fz   = 50 + 30*rand(Z,1);      % nominal compute capacity
prob.Pidle = 0.4 + 0.2*rand(Z,1);   % edge idle power
prob.Ppeak = prob.Pidle + (0.8 + 0.6*rand(Z,1)); % edge peak power

% Time-varying base load and demands with scenario variability
% (Positive, with daily-ish profile)
t = (1:T)';
daily = 0.6 + 0.4*sin(2*pi*(t/T));
daily = daily - min(daily) + 0.2;

Pbase = zeros(Z,T,W);
PEVreq = zeros(Z,T,W);
Wdem = zeros(Z,T,W);
lamE = zeros(Z,T,W);
lamS = zeros(Z,T,W);

for w = 1:W
    shock = 0.8 + 0.6*rand;  % scenario scaling
    for z = 1:Z
        base_level = 10 + 8*rand;
        ev_level   = 8 + 6*rand;
        cmp_level  = 30 + 20*rand;

        noise_b = 0.3*randn(T,1);
        noise_e = 0.6*randn(T,1);
        noise_c = 0.6*randn(T,1);

        Pbase(z,:,w) = max(0, shock*(base_level*daily + noise_b));
        PEVreq(z,:,w) = max(0, shock*(ev_level*(daily.^1.2) + noise_e));
        Wdem(z,:,w) = max(0, shock*(cmp_level*(daily.^1.1) + noise_c));
    end

    % prices (keep positive)
    base_price = 0.6 + 0.2*sin(2*pi*(t/T) + 0.7) + 0.05*randn(T,1);
    base_price = max(0.2, base_price);

    serv_price = 0.2 + 0.1*cos(2*pi*(t/T) + 1.3) + 0.03*randn(T,1);
    serv_price = max(0.05, serv_price);

    for z = 1:Z
        lamE(z,:,w) = max(0.1, base_price' .* (0.9 + 0.2*rand));
        lamS(z,:,w) = max(0.05, serv_price' .* (0.9 + 0.2*rand));
    end
end

prob.Pbase = Pbase;
prob.PEVreq = PEVreq;
prob.Wdem = Wdem;
prob.lambda_e = lamE;
prob.lambda_s = lamS;
end

function f = eval_f123_synthetic(u, prob)
% Evaluate f1,f2,f3 using paper-consistent definitions (no OPF feasibility layer).
% Decision u = [u_ch(1..Z); u_cp(1..Z)] in [0,1]^(2Z).
Z = prob.Z; T = prob.T; W = prob.W;

u = u(:);
u_ch = min(1,max(0,u(1:Z)));
u_cp = min(1,max(0,u(Z+1:2*Z)));

dt = prob.dt;
piw = prob.piw;

% Precompute quota-limited envelopes
P_allow = u_ch .* prob.Pmax;         % P_EV,allow(z)
F_allow = u_cp .* prob.Fz;           % F_allow(z)

% Scenario-wise accumulators
PTOT_w = zeros(W,1);
dW_w = zeros(W,1);
L_w = zeros(W,1);

for w = 1:W
    Pbase = prob.Pbase(:,:,w);       % Z x T
    PEVreq = prob.PEVreq(:,:,w);     % Z x T
    Wdem = prob.Wdem(:,:,w);         % Z x T
    lamE = prob.lambda_e(:,:,w);
    lamS = prob.lambda_s(:,:,w);

    % Served EV power and shortfall (elementwise min)
    PEVserv = min(PEVreq, P_allow);
    dPEV = PEVreq - PEVserv;         % shortfall >= 0

    % Served compute and unmet workload
    Wserv = min(Wdem, F_allow);
    dW = Wdem - Wserv;               % unmet >= 0

    % Edge power depends on served utilization ratio rho_serv = Wserv/(Fz+epsF)
    rho = Wserv ./ (prob.Fz + prob.epsF);  % Z x T, with implicit expansion in recent MATLAB
    Ped = prob.Pidle + (prob.Ppeak - prob.Pidle) .* rho; % Z x T

    % Total electrical power per zone/time
    Ptot = Pbase + PEVserv + Ped;    % Z x T

    % f1 components: P_TOT(u,w) = sum_{t,z} Ptot * dt
    PTOT_w(w) = sum(Ptot(:)) * dt;

    % f2 components: DeltaW(u,w) = sum_{t,z} dW
    dW_w(w) = sum(dW(:));

    % Peak overload proxies
    EL = Ptot ./ prob.Pcap;          % Z x T
    oel = max(0, EL - 1);
    Oel = max(oel(:));

    ocmp = dW ./ (F_allow + prob.epsF);  % Z x T
    Ocmp = max(ocmp(:));

    % Scenario-wise operating cost J(u,w) = sum_{t,z} ( lamE*(PEVserv+Ped) - lamS*PEVserv + kappa*dPEV ) * dt
    J = sum( (lamE.*(PEVserv + Ped) - lamS.*PEVserv + prob.kappa_sf.*dPEV), 'all') * dt;

    % Composite loss L(u,w)
    L_w(w) = prob.betaJ*J + prob.beta_el*Oel + prob.beta_cmp*Ocmp;
end

% Objectives
f1 = sum(piw .* PTOT_w);
f2 = sum(piw .* dW_w);
f3 = weighted_cvar(L_w, piw, prob.alpha);

f = [f1; f2; f3];
end

function cvar = weighted_cvar(L, p, alpha)
% Weighted CVaR_alpha for discrete scenarios with probabilities p (sum to 1).
% Define VaR as smallest threshold eta such that P(L<=eta) >= alpha,
% then CVaR = E[L | L >= VaR] in weighted sense (handling mass at VaR properly).
L = L(:); p = p(:);
% Sort by loss
[Ls, idx] = sort(L, 'ascend');
ps = p(idx);
cdf = cumsum(ps);

% Find VaR level
k = find(cdf >= alpha, 1, 'first');
eta = Ls(k);

% Tail expectation beyond eta, with proper handling of probability mass at eta
tail_mask = (Ls > eta);
p_tail = sum(ps(tail_mask));

% Portion at VaR to reach exactly (1-alpha) tail probability
p_at = sum(ps(Ls == eta));
p_needed = max(0, (1 - alpha) - p_tail);
p_use_at = min(p_at, p_needed);

tail_sum = sum(ps(tail_mask) .* Ls(tail_mask));
tail_sum = tail_sum + p_use_at * eta;

den = max(1 - alpha, eps);
cvar = tail_sum / den;
end

function J = fd_jacobian(evalf, u, h)
% Central finite-difference Jacobian of f(u) where f is 3x1.
u = u(:);
n = numel(u);
f0 = evalf(u);
m = numel(f0);
J = zeros(m,n);

for j = 1:n
    ujp = u; ujm = u;
    ujp(j) = min(1, u(j) + h);
    ujm(j) = max(0, u(j) - h);
    fp = evalf(ujp);
    fm = evalf(ujm);
    denom = ujp(j) - ujm(j);
    if denom <= 0
        J(:,j) = 0;
    else
        J(:,j) = (fp - fm) / denom;
    end
end
end
