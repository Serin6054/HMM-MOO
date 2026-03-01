clear; clc;

root_dir = fileparts(mfilename('fullpath'));
addpath(root_dir);
addpath(fullfile(root_dir,'oracle'));

% ---- load scenarios cache ----
cache_file = fullfile(root_dir,'cache','scenarios.mat');
load(cache_file,'scenarios','meta'); %#ok<NASGU>

S = numel(scenarios);
R = scenarios(1).R;
dim = 2*R;

lb = 0.0; ub = 1.0;

% ---- oracle params (optimization uses minibatch; report uses full) ----
params_opt  = oracle_make_params('eval.mode',"minibatch",'eval.B',30,'eval.K_resamp',1,'eval.seed',2025);
params_full = params_opt; params_full.eval.mode = "full";

% ---- PSO opts (shared) ----
opts = struct();
opts.num_particles = 30;
opts.max_iter      = 80;
opts.w_inertia     = 0.7;
opts.c1            = 1.5;
opts.c2            = 1.5;
opts.agent_dim     = 2;

% Kalman-pos
opts.Q_pos  = 1e-4;
opts.R_pos  = 1e-2;
opts.P0_pos = 1e-1;

% VA
opts.beta_va  = 0.85;
opts.gamma_va = 0.15;
opts.eps_va   = 1e-9;

% Kalman-fit (for VA signal)
opts.Q_fit  = 1e-4;
opts.R_fit  = 5e-3;
opts.P0_fit = 1e-1;

opts.verbose = true;

% ---- output dir ----
out_dir = fullfile(root_dir,'results', ['ablation_' datestr(now,'yyyymmdd_HHMMSS')]);
if ~exist(out_dir,'dir'), mkdir(out_dir); end

results = struct();

% ==========================================================
% Variant A: Plain MA-PSO (no Kalman-pos, no VA)
% ==========================================================
rng(1001,'twister');
optsA = opts; optsA.use_kalman_pos=false; optsA.use_va=false; optsA.use_kalman_fit=false;
[uA, FA, hA] = pso_minimize_ma_kalman_va_oracle(scenarios, params_opt, dim, lb, ub, optsA);
fullA = oracle_eval(uA, scenarios, params_full, (1:S).');
results.Plain.u=uA; results.Plain.F=FA; results.Plain.hist=hA; results.Plain.full=fullA;

% ==========================================================
% Variant B: MA-PSO + Kalman-pos (Kalman only)
% ==========================================================
rng(1002,'twister');
optsB = opts; optsB.use_kalman_pos=true; optsB.use_va=false; optsB.use_kalman_fit=false;
[uB, FB, hB] = pso_minimize_ma_kalman_va_oracle(scenarios, params_opt, dim, lb, ub, optsB);
fullB = oracle_eval(uB, scenarios, params_full, (1:S).');
results.KalmanOnly.u=uB; results.KalmanOnly.F=FB; results.KalmanOnly.hist=hB; results.KalmanOnly.full=fullB;

% ==========================================================
% Variant C: MA-PSO + VA (VA only, no Kalman-pos)
% ==========================================================
rng(1003,'twister');
optsC = opts; optsC.use_kalman_pos=false; optsC.use_va=true; optsC.use_kalman_fit=false;
[uC, FC, hC] = pso_minimize_ma_kalman_va_oracle(scenarios, params_opt, dim, lb, ub, optsC);
fullC = oracle_eval(uC, scenarios, params_full, (1:S).');
results.VAOnly.u=uC; results.VAOnly.F=FC; results.VAOnly.hist=hC; results.VAOnly.full=fullC;

% ==========================================================
% Variant D: Full (Kalman-pos + VA + Kalman-fit)
% ==========================================================
rng(1004,'twister');
optsD = opts; optsD.use_kalman_pos=true; optsD.use_va=true; optsD.use_kalman_fit=true;
[uD, FD, hD] = pso_minimize_ma_kalman_va_oracle(scenarios, params_opt, dim, lb, ub, optsD);
fullD = oracle_eval(uD, scenarios, params_full, (1:S).');
results.Full.u=uD; results.Full.F=FD; results.Full.hist=hD; results.Full.full=fullD;

save(fullfile(out_dir,'ablation_results.mat'), 'results', 'params_opt', 'params_full', 'opts', '-v7.3');

fprintf('\n[Step4] Ablation suite done. Saved to:\n  %s\n', out_dir);

% Quick print (so you can immediately judge)
fprintf('\n[Test(full) metrics]\n');
fprintf('  Plain      fitness=%.4g, f1=%.4g f2=%.4g f3=%.4g\n', results.Plain.full.fitness, results.Plain.full.f1, results.Plain.full.f2, results.Plain.full.f3);
fprintf('  KalmanOnly fitness=%.4g, f1=%.4g f2=%.4g f3=%.4g\n', results.KalmanOnly.full.fitness, results.KalmanOnly.full.f1, results.KalmanOnly.full.f2, results.KalmanOnly.full.f3);
fprintf('  VAOnly     fitness=%.4g, f1=%.4g f2=%.4g f3=%.4g\n', results.VAOnly.full.fitness, results.VAOnly.full.f1, results.VAOnly.full.f2, results.VAOnly.full.f3);
fprintf('  Full       fitness=%.4g, f1=%.4g f2=%.4g f3=%.4g\n', results.Full.full.fitness, results.Full.full.f1, results.Full.full.f2, results.Full.full.f3);
