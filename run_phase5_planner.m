%% run_phase5_planner.m
% Phase 5: MOEA/D tri-objective planning with CVaR on compressed scenarios.

clear; clc; rng(42);
addpath(genpath(pwd));
% ---- switches from wrapper ----
sw = struct();
if exist('opts_in','var') && isstruct(opts_in) && isfield(opts_in,'switches')
    sw = opts_in.switches;
end

if USE_KALMAN
USE_KALMAN = ~isfield(sw,'kalman') || sw.kalman==1;
end

if USE_VA
USE_VA     = ~isfield(sw,'va')     || sw.va==1;
end
% ---- Paths / Inputs ----
ART = fullfile(pwd, 'artifacts');
S_agg = load(fullfile(ART,'aggregated_stats.mat'));        % pi_global, A_global, mu_global, sigma2_global, lambda_global
S_cmp = load(fullfile(ART,'compressed_scenarios.mat'));    % scenario_all (R x H x 2), weight_all (R x 1)

scenario_all = S_cmp.scenario_all;    % y (Gaussian) in (:,:,1), c (Poisson) in (:,:,2)
weight_all   = S_cmp.weight_all(:);
[R,H,~] = size(scenario_all);
assert(H==96, 'This script assumes H=96 (15-min slots). Adjust config if needed.');

% ---- Config for demand proxy & cap mapping ----
cfg.H        = H;
cfg.dt_h     = 0.25;         % 15 min -> 0.25 h
cfg.B        = 8;            % blocks (piecewise-constant policy)
cfg.alpha    = 0.05;         % CVaR level
cfg.Pmax     = 550;          % feeder cap scale [kW] (tunable)
cfg.L0       = 350;          % base level [kW] (tunable)
cfg.a_y      = 25;           % kW per unit y_t
cfg.b_c      = 7;            % EVs -> count * p_ev
cfg.p_ev     = 7;            % per-EV kW (7 or 11 typical)
cfg.lambda_tv= 5;            % weight for TV(θ) in f2
cfg.lambda_mu= 2;            % weight for mean(θ) in f2

% ---- MOEA/D Hyper-params ----
P      = 120;    % population / #subproblems
G      = 500;    % generations
T      = 15;     % neighborhood size
pc     = 0.9;    % crossover prob (SBX)
eta_c  = 20;     % SBX eta
pm     = 1/cfg.B;% mutation prob per variable
eta_m  = 15;     % polynomial mutation eta

% Decision bounds
LB = zeros(cfg.B,1);
UB = ones(cfg.B,1);

% ---- Build evaluator (CRN: fixed scenarios and weights) ----
evaluator = @(theta) eval_phase5_objectives(theta, scenario_all, weight_all, cfg);

% ---- Run MOEA/D ----
[pop, F, W, Bidx, best_hist] = moead_solve(P,G,T,LB,UB,pc,eta_c,pm,eta_m,evaluator);

% ---- Select a default operating point via ASF (user can re-pick later) ----
theta_star_idx = pick_asf(F, [0.5 0.25 0.25], min(F,[],1), max(F,[],1)); % weights can be changed
theta_star     = pop(:, theta_star_idx);
F_star         = F(theta_star_idx,:);

% ---- Save artifacts ----
out = fullfile(ART,'phase5_results');
if ~exist(out,'dir'), mkdir(out); end
save(fullfile(out,'moead_phase5.mat'), 'pop','F','W','Bidx','best_hist','theta_star','F_star','cfg');

writematrix(F, fullfile(out,'F_all.csv'));
writematrix(theta_star', fullfile(out,'theta_star.csv'));
writematrix(F_star, fullfile(out,'F_star.csv'));

fprintf('Phase 5 done. Pareto size=%d. Selected ASF point: [%g %g %g]\n', size(F,1), F_star(1),F_star(2),F_star(3));
fprintf('Saved to %s\n', out);

function idx = pick_asf(F, w_asf, z_min, z_max)
% Achievement Scalarizing Function selector (normalize → weighted max).
F = (F - z_min)./max(z_max - z_min, eps);
asf = max( w_asf(:)'.*F, [], 2);
[~, idx] = min(asf);
end
