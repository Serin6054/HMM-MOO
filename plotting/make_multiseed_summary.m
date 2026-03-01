function T = make_multiseed_summary(multiseed_mat_path, out_dir)
% Create mean±std table for (fitness, f1..f3) from full-set evaluation.

if nargin < 2 || isempty(out_dir)
    out_dir = fileparts(multiseed_mat_path);
end
if ~exist(out_dir,'dir'), mkdir(out_dir); end

tmp = load(multiseed_mat_path, 'MS');
MS = tmp.MS;

methods = {'Plain','KalmanOnly','VAOnly','Full'};
n = numel(methods);

Method = strings(n,1);
Fitness_mean = nan(n,1); Fitness_std = nan(n,1);
f1_mean = nan(n,1); f1_std = nan(n,1);
f2_mean = nan(n,1); f2_std = nan(n,1);
f3_mean = nan(n,1); f3_std = nan(n,1);

for i=1:n
    m = methods{i};
    Method(i) = m;

    Ecell = MS.(m).full_eval;
    E = [Ecell{:}];  % cell -> struct array
    
    fit = arrayfun(@(x) x.fitness, E);
    a1  = arrayfun(@(x) x.f1, E);
    a2  = arrayfun(@(x) x.f2, E);
    a3  = arrayfun(@(x) x.f3, E);


    Fitness_mean(i) = mean(fit,'omitnan'); Fitness_std(i)=std(fit,0,'omitnan');
    f1_mean(i) = mean(a1,'omitnan'); f1_std(i)=std(a1,0,'omitnan');
    f2_mean(i) = mean(a2,'omitnan'); f2_std(i)=std(a2,0,'omitnan');
    f3_mean(i) = mean(a3,'omitnan'); f3_std(i)=std(a3,0,'omitnan');
end

T = table(Method, ...
    Fitness_mean,Fitness_std, ...
    f1_mean,f1_std, f2_mean,f2_std, f3_mean,f3_std);

writetable(T, fullfile(out_dir,'multiseed_summary.csv'));
save(fullfile(out_dir,'multiseed_summary.mat'), 'T');

fprintf('[Table] Saved: %s\n', fullfile(out_dir,'multiseed_summary.csv'));
end
