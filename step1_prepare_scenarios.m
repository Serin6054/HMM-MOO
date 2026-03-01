% STEP1_PREPARE_SCENARIOS
% -------------------------------------------------------------------------
% Step 1 of the experimental code: prepare (and cache) the daily scenario set.
%
% This script:
%   1) Validates the required CSV inputs under ./data
%   2) Builds daily scenarios (one day = one scenario)
%   3) Saves a cache to ./cache/scenarios.mat
%   4) Prints a compact sanity-check summary
%
% Usage:
%   Run this script once before running any experiments:
%       >> step1_prepare_scenarios
%
% Notes:
%   - It does NOT change your modeling functions.
%   - It only prepares 'scenarios' and 'meta' for later use.

clear; clc;

root_dir  = fileparts(mfilename('fullpath'));
addpath(root_dir);
data_dir  = fullfile(root_dir, 'data');
cache_dir = fullfile(root_dir, 'cache');
if ~exist(cache_dir, 'dir'), mkdir(cache_dir); end

cache_file = fullfile(cache_dir, 'scenarios.mat');

% ---- 0) Required inputs --------------------------------------------------
req_files = { ...
    'volume.csv', 'e_price.csv', 's_price.csv', ...
    'inf.csv', 'distance.csv', 'weather_central.csv'};
missing = {};
for k = 1:numel(req_files)
    if ~exist(fullfile(data_dir, req_files{k}), 'file')
        missing{end+1} = req_files{k}; %#ok<SAGROW>
    end
end
if ~isempty(missing)
    fprintf('ERROR: missing required CSV(s) under %s\n', data_dir);
    for k = 1:numel(missing)
        fprintf('  - %s\n', missing{k});
    end
    error('Please place the required data files under ./data before continuing.');
end

% ---- 1) Load or build scenarios -----------------------------------------
if exist(cache_file, 'file')
    tmp = load(cache_file, 'scenarios', 'meta');
    scenarios = tmp.scenarios;
    meta      = tmp.meta;
    fprintf('[Step1] Loaded cached scenarios: %s\n', cache_file);
else
    fprintf('[Step1] Building scenarios from CSV...\n');
    scenarios = build_scenarios_from_csv(data_dir);
    meta = local_build_meta(scenarios);
    save(cache_file, 'scenarios', 'meta', '-v7.3');
    fprintf('[Step1] Saved scenarios cache: %s\n', cache_file);
end

% ---- 2) Sanity-check summary --------------------------------------------
fprintf('\n[Scenario summary]\n');
fprintf('  #scenarios (days): %d\n', meta.S);
fprintf('  #zones (R):        %d\n', meta.R);
fprintf('  horizon (T):       %d slots, dt=%.3g hour/slot\n', meta.T, meta.dt);
fprintf('  Pmax:              min=%.1f, median=%.1f, max=%.1f (kW)\n', ...
    min(meta.Pmax), median(meta.Pmax), max(meta.Pmax));
fprintf('  Fcap:              min=%.1f, median=%.1f, max=%.1f (arb./slot)\n', ...
    min(meta.Fcap), median(meta.Fcap), max(meta.Fcap));
fprintf('  price_e:           min=%.4f, median=%.4f, max=%.4f (Yuan/kWh)\n', ...
    meta.price_e_min, meta.price_e_med, meta.price_e_max);
fprintf('  P_req (all):       min=%.2f, median=%.2f, max=%.2f (kW)\n', ...
    meta.Preq_min, meta.Preq_med, meta.Preq_max);
fprintf('  lambda (all):      min=%.2f, median=%.2f, max=%.2f (tasks/h proxy)\n', ...
    meta.lambda_min, meta.lambda_med, meta.lambda_max);
fprintf('  Corr(P_req,lambda): %.3f\n', meta.corr_P_lambda);

% ---- 3) Optional: quick “oracle” smoke test -----------------------------
% Random quotas in [0,1] for a basic end-to-end check.
u0 = rand(1, 2*meta.R);
params0 = default_params_for_smoketest();
[f1,f2,f3,det] = eval_objectives_CVaR(u0, scenarios(1:min(10,meta.S)), params0);
fprintf('\n[Smoke test on first %d scenario(s)]\n', min(10,meta.S));
fprintf('  f1=%.4f, f2=%.4f, f3=%.4f\n', f1,f2,f3);
fprintf('  (details: mean J=%.4f, mean Oel=%.4f, mean Ocmp=%.4f)\n', ...
    mean(det.J), mean(det.Oel), mean(det.Ocmp));

fprintf('\n[Step1] Done. You can now run the experiment scripts (e.g., exp_*).\n');

% -------------------------------------------------------------------------
function meta = local_build_meta(scenarios)
    S  = numel(scenarios);
    R  = scenarios(1).R;
    T  = scenarios(1).T;
    dt = scenarios(1).dt;

    Pmax = scenarios(1).Pmax(:)';
    Fcap = scenarios(1).Fcap(:)';

    % Aggregate stats across all scenarios, zones, time
    Preq_all    = [];
    lambda_all  = [];
    price_e_all = [];
    for s = 1:S
        Preq_all    = [Preq_all;   scenarios(s).P_req_rt(:)];      %#ok<AGROW>
        lambda_all  = [lambda_all; scenarios(s).lambda_req_rt(:)]; %#ok<AGROW>
        price_e_all = [price_e_all; scenarios(s).price_e(:)'];     %#ok<AGROW>
    end

    meta = struct();
    meta.S  = S;
    meta.R  = R;
    meta.T  = T;
    meta.dt = dt;

    meta.Pmax = Pmax;
    meta.Fcap = Fcap;

    meta.Preq_min = min(Preq_all);
    meta.Preq_med = median(Preq_all);
    meta.Preq_max = max(Preq_all);

    meta.lambda_min = min(lambda_all);
    meta.lambda_med = median(lambda_all);
    meta.lambda_max = max(lambda_all);

    meta.price_e_min = min(price_e_all);
    meta.price_e_med = median(price_e_all);
    meta.price_e_max = max(price_e_all);

    if numel(Preq_all) > 2
        C = corrcoef(Preq_all, lambda_all);
        meta.corr_P_lambda = C(1,2);
    else
        meta.corr_P_lambda = NaN;
    end
end

function params = default_params_for_smoketest()
    params = struct();
    params.alpha     = 0.9;
    params.kappa_sf  = 1.0;
    params.beta_J    = 1.0;
    params.beta_el   = 10.0;
    params.beta_cmp  = 5.0;
    params.cap_factor = 1.2;
    params.eps_F     = 1e-6;
end
