% MAIN  Entry point for your experiments.

clear; clc;

data_dir = fullfile(pwd, 'data');

%% ---- Build scenarios from CSV (only needs to run once) ----
scenarios = build_scenarios_from_csv(data_dir);

%% ---- Case B: With vs Without explicit CL objective ----
results_CL = exp_CL_vs_noCL(scenarios);
plot_CL_experiment(results_CL);

improve_CL = (results_CL.f3_nocl - results_CL.f3_cl) / results_CL.f3_nocl * 100;
extra_cost_CL = (results_CL.f1_cl - results_CL.f1_nocl) / results_CL.f1_nocl * 100;
fprintf('Including CL reduces average CL by %.1f%%, with %.1f%% higher expected cost.\n', ...
        improve_CL, extra_cost_CL);


%% ---- Define parameters for baselines and optimization ----
params = oracle_make_params('alpha',0.9,'kappa_sf',0.0, ...
                           'beta_J',1.0,'beta_el',1.0,'beta_cmp',1.0);

%% ---- Baselines ----
baseline_results = run_baselines(scenarios, params);

fprintf('Baseline results (f1,f2,f3):\n');
disp(baseline_results.metrics);

%% ---- Risk-aware vs risk-neutral optimization ----
results_risk = exp_risk_aware_vs_neutral(scenarios);

% Print improvements
improve_CVaR = (results_risk.f3_rn - results_risk.f3_ra) / results_risk.f3_rn * 100;
extra_cost   = (results_risk.f1_ra - results_risk.f1_rn) / results_risk.f1_rn * 100;

fprintf('Risk-aware reduces CVaR by %.1f%%, with %.1f%% higher expected cost.\n', ...
        improve_CVaR, extra_cost);

%% ---- Plot comparison ----
plot_risk_comparison(results_risk);
