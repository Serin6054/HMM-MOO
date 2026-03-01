clear; clc;

root_dir = fileparts(mfilename('fullpath'));
addpath(root_dir);
addpath(fullfile(root_dir,'oracle'));
addpath(fullfile(root_dir,'utils'));

% ---------- load cached scenarios ----------
cache_file = fullfile(root_dir,'cache','scenarios.mat');
if ~exist(cache_file,'file')
    error('Cannot find cache/scenarios.mat. Please run scenario build step first.');
end
load(cache_file,'scenarios');
S = numel(scenarios);

% Infer zones R and decision dimension
if isfield(scenarios(1),'R')
    R = scenarios(1).R;
else
    error('scenarios(1).R not found. Please store R (number of zones) in each scenario.');
end
dim = 2*R;

lb = 0.0; ub = 1.0;

% ---------- base oracle params ----------
% Optimization uses minibatch + CRN; Reporting uses full-Ω
params_opt  = oracle_make_params('eval.mode',"minibatch",'eval.B',30,'eval.K_resamp',1,'eval.seed',2025);
params_full = params_opt; params_full.eval.mode = "full";

% risk-neutral params (lambda_R = 0)
params_opt_RN  = apply_risk_neutral(params_opt);
params_full_RN = apply_risk_neutral(params_full);

% ---------- optimizer shared options ----------
opts_base = struct();
opts_base.num_particles = 30;
opts_base.max_iter      = 80;
opts_base.w_inertia     = 0.7;
opts_base.c1            = 1.5;
opts_base.c2            = 1.5;
opts_base.agent_dim     = 2;

% Kalman-pos
opts_base.Q_pos  = 1e-4;
opts_base.R_pos  = 1e-2;
opts_base.P0_pos = 1e-1;

% VA
opts_base.beta_va  = 0.85;
opts_base.gamma_va = 0.15;
opts_base.eps_va   = 1e-9;

% Kalman-fit (VA signal smoothing)
opts_base.Q_fit  = 1e-4;
opts_base.R_fit  = 5e-3;
opts_base.P0_fit = 1e-1;

opts_base.verbose = false;

% ---------- A1 sweep settings ----------
kappa_list = [0.6, 0.8, 1.0, 1.2, 1.4];   % compute capacity scale
seed_list  = 1001:1010;                  % >=10 seeds recommended
nK = numel(kappa_list);
nSeeds = numel(seed_list);

% ---------- method variants ----------
% Minimal but strong set:
%   RA_Full (risk-aware + Kalman+VA)
%   RN_Full (risk-neutral + Kalman+VA)
%   RA_Plain (risk-aware + plain MA-PSO)
%   RN_Plain (risk-neutral + plain MA-PSO)
variants = { ...
    struct('name',"RA_Full",  'risk',"RA",'use_kalman_pos',true,'use_va',true,'use_kalman_fit',true), ...
    struct('name',"RN_Full",  'risk',"RN",'use_kalman_pos',true,'use_va',true,'use_kalman_fit',true), ...
    struct('name',"RA_Plain", 'risk',"RA",'use_kalman_pos',false,'use_va',false,'use_kalman_fit',false), ...
    struct('name',"RN_Plain", 'risk',"RN",'use_kalman_pos',false,'use_va',false,'use_kalman_fit',false) ...
};

% ---------- output directory ----------
out_dir = fullfile(root_dir,'results', ['caseA_A1_' datestr(now,'yyyymmdd_HHMMSS')]);
if ~exist(out_dir,'dir'), mkdir(out_dir); end

A1 = struct();
A1.kappa_list = kappa_list;
A1.seed_list  = seed_list;
A1.variants   = variants;
A1.R = R; A1.dim = dim;
A1.opts_base = opts_base;

A1.data = cell(numel(variants), nK);  % each cell: struct with bestF_hist/bestU/full_eval/info

fprintf('\n=== Case A / A1: Compute capacity sweep ===\n');
fprintf('Zones R=%d, dim=%d, scenarios S=%d\n', R, dim, S);
fprintf('kappa_F: %s\n', mat2str(kappa_list));
fprintf('seeds:   %s\n', mat2str(seed_list));

for kk = 1:nK
    kappaF = kappa_list(kk);

    % Apply compute capacity scaling ONCE per kappa
    [scen_k_RA, params_opt_k_RA, scale_info_RA]   = apply_compute_capacity_scale(scenarios, params_opt,  kappaF, R);
    [~,         params_full_k_RA, ~]              = apply_compute_capacity_scale(scenarios, params_full, kappaF, R);

    [scen_k_RN, params_opt_k_RN, scale_info_RN]   = apply_compute_capacity_scale(scenarios, params_opt_RN,  kappaF, R);
    [~,         params_full_k_RN, ~]              = apply_compute_capacity_scale(scenarios, params_full_RN, kappaF, R);

    fprintf('\n--- kappa_F = %.2f ---\n', kappaF);
    fprintf('Scaled fields (RA): %s\n', strjoin(scale_info_RA.scaled_param_fields, ', '));
    fprintf('Scaled fields (RN): %s\n', strjoin(scale_info_RN.scaled_param_fields, ', '));

    for v = 1:numel(variants)
        cfg = variants{v};
        name = cfg.name;

        bestF_hist = nan(opts_base.max_iter, nSeeds);
        bestU      = nan(nSeeds, dim);
        full_eval  = cell(nSeeds, 1);

        fprintf('  Variant: %s\n', name);

        % choose risk params/scenarios
        if cfg.risk == "RA"
            scen_k = scen_k_RA;
            p_opt  = params_opt_k_RA;
            p_full = params_full_k_RA;
        else
            scen_k = scen_k_RN;
            p_opt  = params_opt_k_RN;
            p_full = params_full_k_RN;
        end

        for sidx = 1:nSeeds
            seed = seed_list(sidx);
            rng(seed,'twister');

            optsv = opts_base;
            optsv.use_kalman_pos = cfg.use_kalman_pos;
            optsv.use_va         = cfg.use_va;
            optsv.use_kalman_fit = cfg.use_kalman_fit;

            [u, ~, hist] = pso_minimize_ma_kalman_va_oracle(scen_k, p_opt, dim, lb, ub, optsv);
            bestF_hist(:, sidx) = hist.best_F(:);
            bestU(sidx,:) = u;

            out_full = oracle_eval(u, scen_k, p_full, (1:S).');
            full_eval{sidx} = out_full;

            fprintf('    seed=%d  full_fitness=%.6g\n', seed, out_full.fitness);
        end

        cell_data = struct();
        cell_data.kappaF     = kappaF;
        cell_data.variant    = name;
        cell_data.bestF_hist = bestF_hist;
        cell_data.bestU      = bestU;
        cell_data.full_eval  = full_eval;
        cell_data.scale_info = scale_info_RA; % same structure; record once
        A1.data{v,kk} = cell_data;
    end
end

save(fullfile(out_dir,'caseA_A1_results.mat'), 'A1', '-v7.3');
fprintf('\n[Saved] %s\n', fullfile(out_dir,'caseA_A1_results.mat'));
fprintf('[Output dir] %s\n', out_dir);
