function plot_multiseed_convergence(multiseed_mat_path, out_dir)
% Plot mean and +/- std bands (as dashed lines) for each method.

if nargin < 2 || isempty(out_dir)
    out_dir = fileparts(multiseed_mat_path);
end
if ~exist(out_dir,'dir'), mkdir(out_dir); end

tmp = load(multiseed_mat_path, 'MS');
MS = tmp.MS;

methods = {'Plain','KalmanOnly','VAOnly','Full'};

figure; hold on;
for k = 1:numel(methods)
    m = methods{k};
    H = MS.(m).bestF_hist; % [T x nSeeds]
    mu = mean(H, 2, 'omitnan');
    sd = std(H, 0, 2, 'omitnan');

    x = (1:numel(mu)).';
    plot(x, mu, 'LineWidth', 1.8);
    plot(x, mu+sd, '--', 'LineWidth', 1.0);
    plot(x, mu-sd, '--', 'LineWidth', 1.0);
end
grid on;
xlabel('Iteration');
ylabel('Best fitness');
title('Multi-seed convergence (mean \pm std)');

% 将图例放在底部，水平排列
legend({'Plain \mu','Plain \mu\pm\sigma', ...
        'KalmanOnly \mu','KalmanOnly \mu\pm\sigma', ...
        'VAOnly \mu','VAOnly \mu\pm\sigma', ...
        'Full \mu','Full \mu\pm\sigma'}, ...
        'Location', 'southoutside', ...
        'Orientation', 'horizontal', ...
        'NumColumns', 4);  % 分成4列

set(gca,'FontSize',11);
saveas(gcf, fullfile(out_dir,'multiseed_convergence.png'));
% close(gcf);

fprintf('[Plot] Saved: %s\n', fullfile(out_dir,'multiseed_convergence.png'));
end
