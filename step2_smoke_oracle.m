clear; clc;
load(fullfile('cache','scenarios.mat'), 'scenarios');

params = oracle_make_params('alpha',0.90,'lambda_el',1,'lambda_cmp',1,'lambda_R',1);
S = numel(scenarios);

% iteration k=1: get batch indices
omega_idx = oracle_get_batch(1, S, params);

% random u
R = scenarios(1).R;
u = rand(1, 2*R);

out = oracle_eval(u, scenarios, params, omega_idx);

disp(out);
fprintf('fitness=%.6g (f1=%.6g,f2=%.6g,f3=%.6g), S_used=%d\n', ...
    out.fitness,out.f1,out.f2,out.f3,out.S_used);
