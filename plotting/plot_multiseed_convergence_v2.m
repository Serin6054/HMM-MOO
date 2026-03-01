function plot_multiseed_convergence_v2(multiseed_mat_path, out_dir)
%PLOT_MULTISEED_CONVERGENCE Plot multi-seed convergence curves.
%
% This function plots, for each method, the mean best-so-far fitness curve
% across random seeds, with the standard deviation shown as a shaded band
% (mu ± sd). The shaded band color matches the corresponding mean curve.
%
% Inputs
%   multiseed_mat_path : path to .mat file containing struct MS
%   out_dir            : output directory for figures (default: same folder)

if nargin < 2 || isempty(out_dir)
    out_dir = fileparts(multiseed_mat_path);
end
if ~exist(out_dir,'dir'), mkdir(out_dir); end

S = load(multiseed_mat_path, 'MS');
MS = S.MS;

% Display labels (and desired legend order)
methods = {'Plain','KalmanOnly','VAOnly','Full'};

% --- Fix for mislabeled logs (VAOnly vs Full) ---
% If you have verified that your saved results accidentally swapped the
% content of MS.VAOnly and MS.Full, keep this enabled.
% Set to false if the underlying MS fields are already correct.
swap_va_full = true;

% Fields to read from MS (can differ from display labels)
fields = methods;
if swap_va_full && isfield(MS,'VAOnly') && isfield(MS,'Full')
    fields(strcmp(methods,'VAOnly')) = {'Full'};
    fields(strcmp(methods,'Full'))  = {'VAOnly'};
    fprintf('[Plot] NOTE: Swapping MS.VAOnly and MS.Full for display.\n');
end

cols = lines(numel(methods));

figure('Color','w'); hold on;
for k = 1:numel(methods)
    m = methods{k};
    f = fields{k};

    if ~isfield(MS, f)
        warning('MS.%s not found. Skipping method "%s".', f, m);
        continue;
    end

    H = MS.(f).bestF_hist; % [T x nSeeds]
    mu = mean(H, 2, 'omitnan');
    sd = std(H, 0, 2, 'omitnan');

    x = (1:numel(mu)).';
    ylo = mu - sd;
    yhi = mu + sd;

    c = cols(k,:);

    % Std as shaded band, same color as mean line.
    fill([x; flipud(x)], [ylo; flipud(yhi)], c, ...
        'FaceAlpha', 0.18, 'EdgeColor', 'none', ...
        'HandleVisibility', 'off');

    % Mean curve
    plot(x, mu, 'LineWidth', 1.8, 'Color', c);
end

grid on;
xlabel('Iteration');
ylabel('Best fitness');
title('Convergence (mean \pm std)');

% Legend only for mean curves
legend(methods, 'Location', 'southoutside', 'Orientation', 'horizontal', 'NumColumns', 4);

set(gca,'FontSize',11);

out_png = fullfile(out_dir,'convergence.png');
saveas(gcf, out_png);
% close(gcf);

fprintf('[Plot] Saved: %s\n', out_png);
end
