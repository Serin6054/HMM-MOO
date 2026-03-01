clear; clc;

root_dir = fileparts(mfilename('fullpath'));
addpath(root_dir);
addpath(fullfile(root_dir,'plotting'));

% ---- Find the newest ablation result folder automatically ----
res_root = fullfile(root_dir,'results');
d = dir(fullfile(res_root, 'ablation_*'));
if isempty(d)
    error('No ablation_* folder found under ./results. Run step4_run_ablation_suite first.');
end
[~, idx] = max([d.datenum]);
latest_dir = fullfile(res_root, d(idx).name);

mat_path = fullfile(latest_dir, 'ablation_results.mat');
if ~exist(mat_path,'file')
    error('Cannot find ablation_results.mat in %s', latest_dir);
end

% ---- Plot + Table ----
plot_ablation_convergence(mat_path, latest_dir);
T = make_ablation_table(mat_path, latest_dir); %#ok<NASGU>

fprintf('\n[Step5] Done. Outputs in:\n  %s\n', latest_dir);
