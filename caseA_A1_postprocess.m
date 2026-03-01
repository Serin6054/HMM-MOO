clear; clc;

root_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(root_dir,'plotting'));
addpath(fullfile(root_dir,'utils'));
addpath(fullfile(root_dir,'oracle'));

% Find latest A1 folder
latest_dir = find_latest_results_dir(fullfile(root_dir,'results'), "caseA_A1_");
mat_path = fullfile(latest_dir, 'caseA_A1_results.mat');
if ~exist(mat_path,'file')
    error('Cannot find caseA_A1_results.mat in %s', latest_dir);
end

% Load
tmp = load(mat_path,'A1');
A1 = tmp.A1;

% Outputs
a1_make_summary_table(A1, latest_dir);
a1_plot_metrics_vs_kappa(A1, latest_dir);

% Risk CDF at tight kappa (min)
a1_plot_risk_cdf_tight(A1, latest_dir);

% Quota heatmaps at min & max kappa for the main method (RA_Full)
a1_plot_quota_heatmap(A1, latest_dir, "RA_Full");

fprintf('\n[CaseA A1] Postprocess done. Outputs in:\n  %s\n', latest_dir);
