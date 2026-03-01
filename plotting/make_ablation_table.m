function T = make_ablation_table(result_mat_path, out_dir)
%MAKE_ABLATION_TABLE  Create a publication-ready summary table (CSV + MAT).
%
% Inputs:
%   result_mat_path : path to ablation_results.mat
%   out_dir         : output folder (optional)
%
% Output:
%   T : MATLAB table, also saved as ablation_summary.csv and .mat

if nargin < 2 || isempty(out_dir)
    out_dir = fileparts(result_mat_path);
end
if ~exist(out_dir,'dir'), mkdir(out_dir); end

tmp = load(result_mat_path, 'results');
results = tmp.results;

methods = {'Plain','KalmanOnly','VAOnly','Full'};

n = numel(methods);
Method   = strings(n,1);
Fitness  = nan(n,1);
f1       = nan(n,1);
f2       = nan(n,1);
f3       = nan(n,1);
FeasRate = nan(n,1);
TimeSec  = nan(n,1);

for i=1:n
    m = methods{i};
    Method(i)  = m;

    full = results.(m).full;
    Fitness(i) = full.fitness;
    f1(i)      = full.f1;
    f2(i)      = full.f2;
    f3(i)      = full.f3;

    if isfield(full,'feas_rate') && ~isempty(full.feas_rate)
        FeasRate(i) = full.feas_rate;
    else
        % try to infer from det if it exists
        FeasRate(i) = local_infer_feas_rate(full);
    end

    if isfield(full,'time_sec')
        TimeSec(i) = full.time_sec;
    end
end

T = table(Method, Fitness, f1, f2, f3, FeasRate, TimeSec);

% optional: sort by Fitness
T = sortrows(T, 'Fitness', 'ascend');

writetable(T, fullfile(out_dir,'ablation_summary.csv'));
save(fullfile(out_dir,'ablation_summary.mat'), 'T');

fprintf('[Table] Saved: %s\n', fullfile(out_dir,'ablation_summary.csv'));
fprintf('[Table] Saved: %s\n', fullfile(out_dir,'ablation_summary.mat'));
end

function feas = local_infer_feas_rate(full)
feas = NaN;
if ~isfield(full,'det') || ~isstruct(full.det), return; end
det = full.det;

if isfield(det,'feasible')
    feas = mean(det.feasible(:));
elseif isfield(det,'flag_inf')
    feas = mean(det.flag_inf(:)==0);
elseif isfield(det,'flags')
    feas = mean(det.flags(:)==0);
end
end
