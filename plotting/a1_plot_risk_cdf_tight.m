function a1_plot_risk_cdf_tight(A1, out_dir)
if ~exist(out_dir,'dir'), mkdir(out_dir); end

% Use smallest kappa as the "tight" point
[~, kk] = min(A1.kappa_list);

% Plot only the most meaningful comparison by default
plot_methods = ["RN_Full","RA_Full","RN_Plain","RA_Plain"];

% Reload scenarios (to be safe)
root_dir = fileparts(fileparts(mfilename('fullpath')));
load(fullfile(root_dir,'cache','scenarios.mat'), 'scenarios');
S = numel(scenarios);

% We need params_full for this kappa; reuse from stored runs:
% We'll take params from the best-seed evaluation implicitly via oracle_eval calls.
% Composite proxy uses lambda_el/lambda_cmp from oracle_make_params (consistent across runs).
params_full_base = oracle_make_params('eval.mode',"full",'eval.B',30,'eval.K_resamp',1,'eval.seed',2025);

lambda_el  = getfield_default(params_full_base, 'lambda_el', 1.0);
lambda_cmp = getfield_default(params_full_base, 'lambda_cmp', 1.0);

figure; hold on;

for m = 1:numel(plot_methods)
    method = plot_methods(m);

    [u_best, scen_k, params_full_k] = a1_pick_best_solution(A1, method, kk, scenarios);

    % scenario-wise composite proxy
    vals = nan(S,1);
    for w = 1:S
        out = oracle_eval(u_best, scen_k, params_full_k, w);
        vals(w) = out.f1 + lambda_el*out.f2 + lambda_cmp*out.f3;
    end

    [xs, ys] = ecdf_local(vals);
    plot(xs, ys, 'LineWidth', 1.8);
end

grid on;
xlabel('Scenario-wise composite proxy (cost + \lambda_{el} f_2 + \lambda_{cmp} f_3)');
ylabel('Empirical CDF');
legend(plot_methods, 'Location','southeast');
title(sprintf('Case A / A1: Risk profile CDF at tight compute capacity (kappa_F=%.2f)', A1.kappa_list(kk)));
set(gca,'FontSize',11);

saveas(gcf, fullfile(out_dir, sprintf('A1_risk_cdf_kappa_%0.2f.png', A1.kappa_list(kk))));
close(gcf);

fprintf('[A1] Saved risk CDF plot.\n');
end

function v = getfield_default(s, f, d)
if isfield(s,f), v = s.(f); else, v = d; end
end

function [x,y] = ecdf_local(v)
v = v(:); v = v(~isnan(v));
v = sort(v,'ascend');
n = numel(v);
x = v;
y = (1:n).'/n;
end
