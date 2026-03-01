function plot_ablation_convergence(result_mat_path, out_dir)
%PLOT_ABLATION_CONVERGENCE  Plot convergence curves for ablation suite.
%
% Inputs:
%   result_mat_path : path to ablation_results.mat
%   out_dir         : output folder for figures (optional)
%
% Output:
%   convergence_ablation.png saved in out_dir.

if nargin < 2 || isempty(out_dir)
    out_dir = fileparts(result_mat_path);
end
if ~exist(out_dir,'dir'), mkdir(out_dir); end

tmp = load(result_mat_path, 'results');
results = tmp.results;

names = {'Plain','KalmanOnly','VAOnly','Full'};
styles = {'-','-','-','-'}; %#ok<NASGU>

figure; hold on;
for k=1:numel(names)
    nm = names{k};
    h = results.(nm).hist;
    y = h.best_F(:);
    x = (1:numel(y)).';
    plot(x, y, 'LineWidth', 1.6); %#ok<*PLOT>
end
grid on;
xlabel('Iteration');
ylabel('Best fitness');
legend(names, 'Location','northeast');
title('Ablation Convergence (Oracle + CRN mini-batch)');

% nicer axis
set(gca,'FontSize',11);

saveas(gcf, fullfile(out_dir,'convergence_ablation.png'));
close(gcf);

fprintf('[Plot] Saved: %s\n', fullfile(out_dir,'convergence_ablation.png'));
end
