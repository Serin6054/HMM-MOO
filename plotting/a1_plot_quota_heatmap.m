function a1_plot_quota_heatmap(A1, out_dir, method_name)
if nargin < 3, method_name = "RA_Full"; end
if ~exist(out_dir,'dir'), mkdir(out_dir); end

% kappa indices: min and max
[~, kmin] = min(A1.kappa_list);
[~, kmax] = max(A1.kappa_list);

root_dir = fileparts(fileparts(mfilename('fullpath')));
load(fullfile(root_dir,'cache','scenarios.mat'), 'scenarios');
R = A1.R;

% Plot for both ends
for kk = [kmin, kmax]
    [u_best, ~, ~] = a1_pick_best_solution(A1, method_name, kk, scenarios);

    % Assumed ordering: u = [u_ch(1:R), u_cp(1:R)]  (stacked)
    u_ch = u_best(1:R);
    u_cp = u_best(R+1:2*R);

    % Heatmap (2 x R)
    U = [u_ch(:)'; u_cp(:)'];

    figure;
    imagesc(U);
    colormap('parula');
    colorbar;

    yticks([1 2]);
    yticklabels({'u^{ch}','u^{cp}'});
    xticks(1:R);
    xlabel('Zone index z');
    title(sprintf('Case A / A1: %s quota structure (kappa_F=%.2f)', method_name, A1.kappa_list(kk)));
    set(gca,'FontSize',11);

    fname = fullfile(out_dir, sprintf('A1_quota_heatmap_%s_kappa_%0.2f.png', method_name, A1.kappa_list(kk)));
    saveas(gcf, fname);
    close(gcf);

    % Save also as CSV for reproducibility
    T = table((1:R).', u_ch(:), u_cp(:), 'VariableNames', {'zone','u_ch','u_cp'});
    writetable(T, fullfile(out_dir, sprintf('A1_quota_%s_kappa_%0.2f.csv', method_name, A1.kappa_list(kk))));
end

fprintf('[A1] Saved quota heatmaps + CSV for %s.\n', method_name);
end
