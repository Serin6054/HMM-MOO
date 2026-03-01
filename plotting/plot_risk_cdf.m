function plot_risk_cdf(multiseed_mat_path, out_dir)
% Risk CDF plots over scenarios for the best-seed solution of each method.

if nargin < 2 || isempty(out_dir)
    out_dir = fileparts(multiseed_mat_path);
end
if ~exist(out_dir,'dir'), mkdir(out_dir); end

tmp = load(multiseed_mat_path, 'MS');
MS = tmp.MS;

% Need oracle to evaluate per-scenario
root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(root_dir);
addpath(fullfile(root_dir,'oracle'));

% Reload scenarios from cache
load(fullfile(root_dir,'cache','scenarios.mat'), 'scenarios');
S = numel(scenarios);

methods = {'Plain','KalmanOnly','VAOnly','Full'};

% Use full params (same as in MS)
params_full = MS.params_full;

% We plot CDF of:
%   (1) scenario cost proxy ~ out.f1 when omega_idx is single scenario
%   (2) composite proxy ~ out.f1 + lambda_el*out.f2 + lambda_cmp*out.f3
% (lambda_R excluded so it does not “double count” CVaR)
lambda_el  = params_full.lambda_el;
lambda_cmp = params_full.lambda_cmp;

% Collect per-method arrays
cost_map = struct();
comp_map = struct();

for k = 1:numel(methods)
    m = methods{k};

    % pick best seed by full-set fitness
    Ecell = MS.(m).full_eval;
    E = [Ecell{:}];
    fit = arrayfun(@(x) x.fitness, E);

    [~, best_idx] = min(fit);
    u = MS.(m).bestU(best_idx,:);

    cost = zeros(S,1);
    comp = zeros(S,1);

    for w = 1:S
        out = oracle_eval(u, scenarios, params_full, w); % single-scenario
        cost(w) = out.f1;
        comp(w) = out.f1 + lambda_el*out.f2 + lambda_cmp*out.f3;
    end

    cost_map.(m) = cost;
    comp_map.(m) = comp;
end

% ---- Plot CDF: cost ----
figure; hold on;
for k=1:numel(methods)
    m = methods{k};
    [xs, ys] = local_ecdf(cost_map.(m));
    plot(xs, ys, 'LineWidth', 1.7);
end
grid on;
xlabel('Scenario-wise cost proxy');
ylabel('Empirical CDF');
legend(methods, 'Location','southeast');
title('Risk profile: scenario-wise cost (CDF)');
set(gca,'FontSize',11);
saveas(gcf, fullfile(out_dir,'risk_cdf_cost.png'));
close(gcf);
fprintf('[Plot] Saved: %s\n', fullfile(out_dir,'risk_cdf_cost.png'));

% ---- Plot CDF: composite proxy ----
figure; hold on;
for k=1:numel(methods)
    m = methods{k};
    [xs, ys] = local_ecdf(comp_map.(m));
    plot(xs, ys, 'LineWidth', 1.7);
end
grid on;
xlabel('Scenario-wise composite proxy (cost + \lambda_{el} f_2 + \lambda_{cmp} f_3)');
ylabel('Empirical CDF');
legend(methods, 'Location','southeast');
title('Risk profile: scenario-wise composite proxy (CDF)');
set(gca,'FontSize',11);
saveas(gcf, fullfile(out_dir,'risk_cdf_composite.png'));
close(gcf);
fprintf('[Plot] Saved: %s\n', fullfile(out_dir,'risk_cdf_composite.png'));

end

function [x,y] = local_ecdf(v)
v = v(:);
v = v(~isnan(v));
v = sort(v, 'ascend');
n = numel(v);
x = v;
y = (1:n).'/n;
end
