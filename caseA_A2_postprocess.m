clear; clc;
% CASEA_A2_POSTPROCESS
% Postprocess A2 results -> summary CSV + a couple diagnostic plots.
%
% Outputs in the same directory as caseA_A2_results.mat:
%   - caseA_A2_summary.csv  (mean ± std on TEST set for each kappa_SF & variant)
%   - caseA_A2_quota_degeneration.csv (fraction of near-zero u_ch; mean u_ch/u_cp)
%   - caseA_A2_plots.png    (quick-look plot pack)

root_dir = fileparts(mfilename('fullpath'));
addpath(root_dir);
addpath(fullfile(root_dir,'oracle'));
addpath(fullfile(root_dir,'utils'));

% find latest A2 dir
res_root = fullfile(root_dir,'results');
d = dir(fullfile(res_root,'caseA_A2_*'));
if isempty(d), error('No caseA_A2_* results found. Run caseA_A2_run_service_penalty_sweep first.'); end
[~,idx] = max([d.datenum]);
out_dir = fullfile(res_root, d(idx).name);

mat_file = fullfile(out_dir,'caseA_A2_results.mat');
if exist(mat_file,'file')~=2
    error('Missing %s', mat_file);
end
load(mat_file,'A2');

klist = A2.kappa_sf_list;
variants = A2.variants;
R = A2.R; dim = A2.dim;

nV = numel(variants);
nK = numel(klist);

% We also need test scenarios to compute service ratio + quota degeneracy stats.
cache_test = fullfile(root_dir,'cache','scenarios_test.mat');
cache_all  = fullfile(root_dir,'cache','scenarios.mat');
if exist(cache_test,'file')==2
    St = load(cache_test,'scenarios_test');
    scenarios_test = St.scenarios_test;
else
    S0 = load(cache_all,'scenarios');
    scenarios_test = S0.scenarios;
end

TBL = {};
TBL2 = {};

for kk = 1:nK
    kSF = klist(kk);
    for v = 1:nV
        cell_data = A2.data{v,kk};
        name = cell_data.variant;

        outs = cell_data.out_test;
        nSeeds = numel(outs);

        f1 = nan(nSeeds,1); f2=f1; f3=f1; fit=f1;
        J   = nan(nSeeds,1);
        Oel = nan(nSeeds,1);
        Ocmp= nan(nSeeds,1);

        % quota degeneracy / averages
        frac_u_ch_zero = nan(nSeeds,1);
        mean_u_ch      = nan(nSeeds,1);
        mean_u_cp      = nan(nSeeds,1);

        served_ratio   = nan(nSeeds,1); % computed deterministically from u_ch & P_req_rt

        for s=1:nSeeds
            o = outs{s};
            f1(s)=o.f1; f2(s)=o.f2; f3(s)=o.f3; fit(s)=o.fitness;

            if isfield(o,'det') && isfield(o.det,'J')
                J(s) = mean(o.det.J);
            end
            if isfield(o,'det') && isfield(o.det,'Oel')
                Oel(s) = mean(o.det.Oel);
            end
            if isfield(o,'det') && isfield(o.det,'Ocmp')
                Ocmp(s) = mean(o.det.Ocmp);
            end

            u = cell_data.bestU(s,:);
            u_ch = u(1:R); u_cp = u(R+1:2*R);

            frac_u_ch_zero(s) = mean(u_ch <= 0.05);
            mean_u_ch(s) = mean(u_ch);
            mean_u_cp(s) = mean(u_cp);

            served_ratio(s) = compute_ev_served_ratio(u_ch, scenarios_test);
        end

        row = {kSF, name, ...
            mean(f1,'omitnan'), std(f1,'omitnan'), ...
            mean(f2,'omitnan'), std(f2,'omitnan'), ...
            mean(f3,'omitnan'), std(f3,'omitnan'), ...
            mean(fit,'omitnan'), std(fit,'omitnan'), ...
            mean(J,'omitnan'), std(J,'omitnan'), ...
            mean(Oel,'omitnan'), std(Oel,'omitnan'), ...
            mean(Ocmp,'omitnan'), std(Ocmp,'omitnan'), ...
            mean(served_ratio,'omitnan'), std(served_ratio,'omitnan')};

        TBL(end+1,:) = row; %#ok<AGROW>

        row2 = {kSF, name, ...
            mean(frac_u_ch_zero,'omitnan'), std(frac_u_ch_zero,'omitnan'), ...
            mean(mean_u_ch,'omitnan'), std(mean_u_ch,'omitnan'), ...
            mean(mean_u_cp,'omitnan'), std(mean_u_cp,'omitnan')};

        TBL2(end+1,:) = row2; %#ok<AGROW>
    end
end

hdr = {'kappa_SF','variant', ...
       'f1_mean','f1_std','f2_mean','f2_std','f3_mean','f3_std', ...
       'fitness_mean','fitness_std', ...
       'J_mean','J_std','Oel_mean','Oel_std','Ocmp_mean','Ocmp_std', ...
       'served_ratio_mean','served_ratio_std'};
write_cell_csv(fullfile(out_dir,'caseA_A2_summary.csv'), hdr, TBL);

hdr2 = {'kappa_SF','variant', ...
        'frac_u_ch_le_0p05_mean','frac_u_ch_le_0p05_std', ...
        'u_ch_mean','u_ch_std','u_cp_mean','u_cp_std'};
write_cell_csv(fullfile(out_dir,'caseA_A2_quota_degeneration.csv'), hdr2, TBL2);

% Quick-look plot: served_ratio + frac u_ch zero vs kappa_SF for two representative variants
try
    plot_quicklook(out_dir, TBL, TBL2);
catch ME
    warning('Plotting failed: %s', ME.message);
end

fprintf('[A2 Postprocess] Wrote:\n  %s\n  %s\n', ...
    fullfile(out_dir,'caseA_A2_summary.csv'), fullfile(out_dir,'caseA_A2_quota_degeneration.csv'));

% ---------------- helper functions ----------------
function r = compute_ev_served_ratio(u_ch, scenarios)
    % Deterministic served ratio from charging quota only (matches sim_one_scenario logic).
    S = numel(scenarios);
    served = 0; req = 0;
    for s = 1:S
        P_req = scenarios(s).P_req_rt;  % [R x T]
        dt    = scenarios(s).dt;
        Pmax  = scenarios(s).Pmax(:);   % [R x 1]
        P_allow = u_ch(:) .* Pmax;      % [R x 1]
        % broadcast min(P_req, P_allow)
        P_serv = min(P_req, P_allow);
        served = served + sum(P_serv(:)) * dt;
        req    = req    + sum(P_req(:))  * dt;
    end
    r = served / max(req, 1e-9);
end

function write_cell_csv(path, header, C)
    fid = fopen(path,'w');
    if fid<0, error('Cannot open %s', path); end
    fprintf(fid, '%s\n', strjoin(header, ','));
    for i=1:size(C,1)
        row = C(i,:);
        parts = cell(1,numel(row));
        for j=1:numel(row)
            x = row{j};
            if isstring(x) || ischar(x)
                parts{j} = char(x);
            else
                parts{j} = sprintf('%.10g', x);
            end
        end
        fprintf(fid, '%s\n', strjoin(parts, ','));
    end
    fclose(fid);
end

function plot_quicklook(out_dir, TBL, TBL2)
    % Convert to arrays
    kappa = cell2mat(TBL(:,1));
    variant = string(TBL(:,2));
    served_mean = cell2mat(TBL(:,15));
    served_std  = cell2mat(TBL(:,16));

    kappa2 = cell2mat(TBL2(:,1));
    variant2 = string(TBL2(:,2));
    frac0_mean = cell2mat(TBL2(:,3));
    frac0_std  = cell2mat(TBL2(:,4));

    reps = ["RN_Plain","RN_Full","RA_Plain","RA_Full"];

    % -------- Plot 1: served ratio --------
    fig1 = figure('Position',[100 100 560 450], 'Color','w');
    ax1 = axes(fig1); hold(ax1,'on');

    for r=1:numel(reps)
        msk = variant==reps(r);
        if ~any(msk), continue; end
        [ks,ord] = sort(kappa(msk));
        sm = served_mean(msk); sm = sm(ord);
        ss = served_std(msk);  ss = ss(ord);
        errorbar(ax1, ks, sm, ss, '-o', 'LineWidth', 1.2);
    end
    xlabel(ax1,'\kappa_{SF}');
    ylabel(ax1,'EV served ratio (mean \pm std)');
    grid(ax1,'on');
    legend(ax1, reps, 'Location','best');
    title(ax1,'Service satisfaction vs shortfall-penalty');

    exportgraphics(fig1, fullfile(out_dir,'caseA_A2_served_ratio.png'));
    close(fig1);

    % -------- Plot 2: corner-solution proxy --------
    fig2 = figure('Position',[100 100 560 450], 'Color','w');
    ax2 = axes(fig2); hold(ax2,'on');

    for r=1:numel(reps)
        msk = variant2==reps(r);
        if ~any(msk), continue; end
        [ks,ord] = sort(kappa2(msk));
        fm = frac0_mean(msk); fm = fm(ord);
        fs = frac0_std(msk);  fs = fs(ord);
        errorbar(ax2, ks, fm, fs, '-o', 'LineWidth', 1.2);
    end
    xlabel(ax2,'\kappa_{SF}');
    ylabel(ax2,'Fraction');
    grid(ax2,'on');
    legend(ax2, reps, 'Location','best');
    % title(ax2,'Corner-solution proxy vs shortfall-penalty');

    exportgraphics(fig2, fullfile(out_dir,'caseA_A2_frac_u_ch_zero.png'));
    close(fig2);
end
