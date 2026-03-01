clear; clc;

root_dir = fileparts(mfilename('fullpath'));
addpath(root_dir);
addpath(fullfile(root_dir,'oracle'));

% ---- load scenarios cache (Step1 output) ----
cache_file = fullfile(root_dir,'cache','scenarios.mat');
if exist(cache_file,'file')
    load(cache_file,'scenarios','meta');
else
    scenarios = build_scenarios_from_csv(fullfile(root_dir,'data'));
    meta = struct(); %#ok<NASGU>
    if ~exist(fullfile(root_dir,'cache'),'dir'), mkdir(fullfile(root_dir,'cache')); end
    save(cache_file,'scenarios','meta','-v7.3');
end

S = numel(scenarios);
R = scenarios(1).R;
dim = 2*R;

% ---- PSO options ----
opts = struct();
opts.num_particles = 30;
opts.max_iter      = 80;
opts.w_inertia     = 0.7;
opts.c1            = 1.5;
opts.c2            = 1.5;
opts.agent_dim     = 2;
opts.Q_scale       = 1e-4;
opts.R_scale       = 1e-2;
opts.P0            = 1e-1;
opts.verbose       = true;

lb = 0.0; ub = 1.0;

% ---- params: optimizer uses minibatch; final report uses full ----
params_opt  = oracle_make_params('eval.mode',"minibatch",'eval.B',30,'eval.K_resamp',1,'eval.seed',2025);
params_full = params_opt; params_full.eval.mode = "full";

% ---- results dir ----
out_dir = fullfile(root_dir,'results', datestr(now,'yyyymmdd_HHMMSS'));
if ~exist(out_dir,'dir'), mkdir(out_dir); end

% ================================================================
% Exp-1: risk-neutral vs risk-aware (use MA-Kalman oracle PSO)
% ================================================================
rng(2025,'twister');

% risk-neutral: [1, 2, 1, 0] -> lambda_el=2, lambda_cmp=1, lambda_R=0
p_rn = params_opt; p_rn.lambda_el=2.0; p_rn.lambda_cmp=1.0; p_rn.lambda_R=0.0;
[u_rn, F_rn, hist_rn] = pso_minimize_ma_kalman_oracle(scenarios, p_rn, dim, lb, ub, opts);
out_rn_full = oracle_eval(u_rn, scenarios, params_full, (1:S).');

% risk-aware: [1, 1.5, 1, 5] -> lambda_el=1.5, lambda_cmp=1, lambda_R=5
p_ra = params_opt; p_ra.lambda_el=1.5; p_ra.lambda_cmp=1.0; p_ra.lambda_R=5.0;
[u_ra, F_ra, hist_ra] = pso_minimize_ma_kalman_oracle(scenarios, p_ra, dim, lb, ub, opts);
out_ra_full = oracle_eval(u_ra, scenarios, params_full, (1:S).');

results_risk = struct();
results_risk.u_rn = u_rn; results_risk.F_rn = F_rn; results_risk.hist_rn = hist_rn; results_risk.full_rn = out_rn_full;
results_risk.u_ra = u_ra; results_risk.F_ra = F_ra; results_risk.hist_ra = hist_ra; results_risk.full_ra = out_ra_full;

save(fullfile(out_dir,'exp1_risk_compare.mat'), 'results_risk');

% ================================================================
% Exp-2: with-CL vs no-CL (use MA-Kalman oracle PSO)
% ================================================================
rng(2026,'twister');

% no-CL: [1,2,0,1] -> lambda_el=2, lambda_cmp=0, lambda_R=1
p_nocl = params_opt; p_nocl.lambda_el=2.0; p_nocl.lambda_cmp=0.0; p_nocl.lambda_R=1.0;
[u_nocl, F_nocl, hist_nocl] = pso_minimize_ma_kalman_oracle(scenarios, p_nocl, dim, lb, ub, opts);
out_nocl_full = oracle_eval(u_nocl, scenarios, params_full, (1:S).');

% with-CL: [1,2,3,1] -> lambda_el=2, lambda_cmp=3, lambda_R=1
p_cl = params_opt; p_cl.lambda_el=2.0; p_cl.lambda_cmp=3.0; p_cl.lambda_R=1.0;
[u_cl, F_cl, hist_cl] = pso_minimize_ma_kalman_oracle(scenarios, p_cl, dim, lb, ub, opts);
out_cl_full = oracle_eval(u_cl, scenarios, params_full, (1:S).');

results_cl = struct();
results_cl.u_nocl = u_nocl; results_cl.F_nocl = F_nocl; results_cl.hist_nocl = hist_nocl; results_cl.full_nocl = out_nocl_full;
results_cl.u_cl   = u_cl;   results_cl.F_cl   = F_cl;   results_cl.hist_cl   = hist_cl;   results_cl.full_cl   = out_cl_full;

save(fullfile(out_dir,'exp2_cl_compare.mat'), 'results_cl');

fprintf('\n[Step3] Done. Results saved to:\n  %s\n', out_dir);
