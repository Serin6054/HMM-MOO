function exp_plot_bus_load_bar_caseA(which_set)
%EXP_PLOT_BUS_LOAD_BAR_CASEA
% 33-bus 节点负载对比柱状图：
% baseline: 仅OPF判定但未使用本文方法优化（u=1）
% optimized: OPF判定 + 本文方法优化（FULL最优解）
%
% 依赖：
%   step1_prepare_scenarios.m  -> cache/scenarios.mat
%   step1b_make_design_test_split.m -> cache/split.mat
%   step8_run_caseA_methods.m  -> results/caseA_methods_*/caseA_methods_results.mat
%
% 用法：
%   exp_plot_bus_load_bar_caseA('test');
%   exp_plot_bus_load_bar_caseA('design');

if nargin<1 || isempty(which_set), which_set = 'test'; end
which_set = lower(string(which_set));

root_dir = fileparts(mfilename('fullpath'));
addpath(root_dir);
addpath(fullfile(root_dir,'utils'));

% 找到最新一次 methods 结果目录
res_root = fullfile(root_dir,'results');
out_dir  = find_latest_results_dir(res_root, "caseA_methods_");
matfile  = fullfile(out_dir,'caseA_methods_results.mat');

if ~exist(matfile,'file')
    error('Missing %s. Please run step8_run_caseA_methods first.', matfile);
end

% baseline_mode='plain' => u=1（未优化），符合你描述的“仅通过OPF但未使用本文方法优化”
step10_plot_bus_load_bar_caseA(matfile, which_set, 'plain');

% 保存图片（可选）
png_out = fullfile(out_dir, sprintf('bus_load_bar_%s_plain_vs_FULL.png', which_set));
try
    exportgraphics(gcf, png_out, 'Resolution', 300);
    fprintf('Saved figure: %s\n', png_out);
catch
    % 兼容旧版本MATLAB
    print(gcf, '-dpng', '-r300', png_out);
    fprintf('Saved figure: %s\n', png_out);
end
end
