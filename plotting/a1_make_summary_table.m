function T = a1_make_summary_table(A1, out_dir)
if ~exist(out_dir,'dir'), mkdir(out_dir); end

kappa = A1.kappa_list;
variants = A1.variants;
nV = numel(variants); nK = numel(kappa);

rows = nV*nK;
Method = strings(rows,1);
KappaF = nan(rows,1);

Fitness_mean = nan(rows,1); Fitness_std = nan(rows,1);
f1_mean = nan(rows,1); f1_std = nan(rows,1);
f2_mean = nan(rows,1); f2_std = nan(rows,1);
f3_mean = nan(rows,1); f3_std = nan(rows,1);

r = 1;
for v=1:nV
    for kk=1:nK
        cell_data = A1.data{v,kk};
        Ecell = cell_data.full_eval;
        E = [Ecell{:}];

        Method(r) = variants{v}.name;
        KappaF(r) = kappa(kk);

        Fitness_mean(r) = mean([E.fitness],'omitnan'); Fitness_std(r)=std([E.fitness],0,'omitnan');
        f1_mean(r) = mean([E.f1],'omitnan'); f1_std(r)=std([E.f1],0,'omitnan');
        f2_mean(r) = mean([E.f2],'omitnan'); f2_std(r)=std([E.f2],0,'omitnan');
        f3_mean(r) = mean([E.f3],'omitnan'); f3_std(r)=std([E.f3],0,'omitnan');

        r = r + 1;
    end
end

T = table(Method, KappaF, ...
    Fitness_mean, Fitness_std, ...
    f1_mean, f1_std, f2_mean, f2_std, f3_mean, f3_std);

T = sortrows(T, {'KappaF','Method'});

writetable(T, fullfile(out_dir,'A1_summary_mean_std.csv'));
save(fullfile(out_dir,'A1_summary_mean_std.mat'),'T');

fprintf('[A1] Saved: %s\n', fullfile(out_dir,'A1_summary_mean_std.csv'));
end
