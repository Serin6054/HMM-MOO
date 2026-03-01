function a1_plot_metrics_vs_kappa(A1, out_dir)
if ~exist(out_dir,'dir'), mkdir(out_dir); end

kappa = A1.kappa_list;
variants = A1.variants;
nV = numel(variants); nK = numel(kappa);

% Choose which metrics to plot (paper-aligned)
metric_names = {'fitness','f1','f2','f3'};
ylabels = { ...
    'Test fitness', ...
    'f1: expected electric-load energy (kWh)', ...
    'f2: expected unmet workload', ...
    'f3: CVaR_{\alpha}(L)' ...
};

for m = 1:numel(metric_names)
    met = metric_names{m};

    mu = nan(nV,nK);
    sd = nan(nV,nK);

    for v=1:nV
        for kk=1:nK
            cell_data = A1.data{v,kk};
            Ecell = cell_data.full_eval;
            E = [Ecell{:}];  % cell -> struct array

            vals = arrayfun(@(x) x.(met), E);
            mu(v,kk) = mean(vals,'omitnan');
            sd(v,kk) = std(vals,0,'omitnan');
        end
    end

    figure; hold on;
    for v=1:nV
        plot(kappa, mu(v,:), 'LineWidth', 1.8);
        plot(kappa, mu(v,:)+sd(v,:), '--', 'LineWidth', 1.0);
        plot(kappa, mu(v,:)-sd(v,:), '--', 'LineWidth', 1.0);
    end
    grid on;
    xlabel('\kappa_F (computing capacity scale)');
    ylabel(ylabels{m});
    leg = strings(1,3*nV);
    idx=1;
    for v=1:nV
        nm = variants{v}.name;
        leg(idx) = nm + " mean"; idx=idx+1;
        leg(idx) = nm + " mean±std"; idx=idx+1;
        leg(idx) = ""; idx=idx+1; % keep spacing
    end
    legend(leg, 'Location','northeastoutside');
    title("Case A / A1: " + met + " vs \kappa_F (mean \pm std)");
    set(gca,'FontSize',11);

    saveas(gcf, fullfile(out_dir, "A1_" + met + "_vs_kappa.png"));
    close(gcf);
end

fprintf('[A1] Saved metric-vs-kappa plots to %s\n', out_dir);
end
