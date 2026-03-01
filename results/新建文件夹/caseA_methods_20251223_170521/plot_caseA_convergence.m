function plot_caseA_convergence(matfile)
% plot_caseA_convergence  Plot two convergence figures from caseA_methods_results.mat
%
% Usage:
%   plot_caseA_convergence('caseA_methods_results.mat')
%   % or if matfile omitted:
%   plot_caseA_convergence

if nargin < 1 || isempty(matfile)
    matfile = 'caseA_methods_results.mat';
end

S = load(matfile, 'results');
results = S.results;

% ---------- Extract histories (seeds x iters) ----------
[H_full, iters]  = get_hist_matrix(results.FULL);
[H_cen,  iters2] = get_hist_matrix(results.Central_PSO);
iters = max(iters, iters2);

[H_ma,  ~] = get_hist_matrix(results.MA_PSO,        iters);
[H_kal, ~] = get_hist_matrix(results.MA_PSO_Kalman, iters);
[H_va,  ~] = get_hist_matrix(results.MA_PSO_VA,     iters);

% Fixed quota has no iterative history -> horizontal line using out_design fitness
y_fixed = get_fixed_level(results.Fixed);
H_fixed = repmat(y_fixed, size(H_full,1), iters);  % match seed count for std=0

x = 1:iters;

% ---------- Figure 1: Fixed / Central / FULL ----------
figure('Name','CaseA Convergence (Fixed, Central-PSO, FULL)','Color','w'); hold on; grid on;
plot_mean_std(x, H_fixed, 'Fixed quota');
plot_mean_std(x, H_cen,   'Central-PSO');
plot_mean_std(x, H_full,  'Proposed');

xlabel('Iteration');
ylabel('Best fitness ');
% title('Convergence: Fixed quota vs Central-PSO vs FULL');
legend('Location','northeast');

% 建议用对数坐标（初始可能有巨额罚项尖峰），不需要就注释掉下一行
set(gca,'YScale','log');

% ---------- Figure 2: MA ablations + FULL ----------
figure('Name','CaseA Convergence (MA family + FULL)','Color','w'); hold on; grid on;
plot_mean_std(x, H_ma,   'MA-PSO');
plot_mean_std(x, H_va,   'MA-PSO + VA');
plot_mean_std(x, H_kal,  'MA-PSO + Kalman');
plot_mean_std(x, H_full, 'Proposed');

xlabel('Iteration');
ylabel('Best fitness ');
% title('Convergence: MA-PSO Ablations vs FULL');
legend('Location','northeast');
set(gca,'YScale','log');

end

% ===================== helpers =====================

function [H, iters] = get_hist_matrix(block, iters_target)
% Return matrix H: nSeeds x iters (padded), and iters length.
% Supports hist{k}.best_F or hist{k}.gbest_F.

nSeeds = numel(block.seeds);
Hcell  = cell(nSeeds,1);
lens   = zeros(nSeeds,1);

for k = 1:nSeeds
    hk = block.hist{k};
    if isempty(hk)
        Hcell{k} = [];
        lens(k) = 0;
        continue;
    end

    if isstruct(hk)
        if isfield(hk,'best_F')
            v = hk.best_F;
        elseif isfield(hk,'gbest_F')
            v = hk.gbest_F;
        elseif isfield(hk,'bestF')
            v = hk.bestF;
        else
            error('Unknown hist field names for method: %s', block.method);
        end
    else
        error('hist{%d} is not a struct for method: %s', k, block.method);
    end

    v = v(:).'; % row vector
    Hcell{k} = v;
    lens(k) = numel(v);
end

iters = max(lens);
if nargin >= 2 && ~isempty(iters_target)
    iters = max(iters, iters_target);
end

H = nan(nSeeds, iters);
for k = 1:nSeeds
    v = Hcell{k};
    if isempty(v)
        continue;
    end
    L = numel(v);
    if L >= iters
        H(k,:) = v(1:iters);
    else
        % pad with last value (best-so-far style)
        H(k,1:L) = v;
        H(k,L+1:end) = v(end);
    end
end
end

function y = get_fixed_level(blockFixed)
% Fixed quota fitness level (design, full evaluation)
nSeeds = numel(blockFixed.seeds);
vals = nan(nSeeds,1);
for k = 1:nSeeds
    outD = blockFixed.out_design{k};
    if isstruct(outD) && isfield(outD,'fitness')
        vals(k) = outD.fitness;
    else
        error('Fixed.out_design{%d} missing fitness.', k);
    end
end
y = mean(vals,'omitnan');
end

function plot_mean_std(x, H, nameStr)
% Plot mean curve with std shaded region (per-iteration across seeds)
% Robust for log-y axis (prevents non-positive lower bound)

mu = mean(H,1,'omitnan');
sd = std(H,0,1,'omitnan');

hLine = plot(x, mu, 'LineWidth', 1.8, 'DisplayName', nameStr);
c = hLine.Color;

y1 = mu ;
y2 = mu ;

ax = gca;
if strcmpi(ax.YScale, 'log')
    % ---- key fix: log axis cannot draw y<=0, clamp lower bound to positive ----
    minPos = min(H(H>0), [], 'all');
    if isempty(minPos) || ~isfinite(minPos)
        minPos = realmin;
    end
    y1 = max(y1, 0.5*minPos);   % clamp to a small positive value
end

hFill = fill([x, fliplr(x)], [y1, fliplr(y2)], c, ...
    'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');

uistack(hFill, 'bottom');
uistack(hLine, 'top');
end
