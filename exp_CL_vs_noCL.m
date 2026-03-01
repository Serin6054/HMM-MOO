function results = exp_CL_vs_noCL(scenarios)
% EXP_CL_VS_NOCL  Compare optimization with vs without explicit CL objective.
%
%   results = exp_CL_vs_noCL(scenarios)
%
%   Produces two optimized quota vectors:
%   - u_nocl : optimized without explicit CL term in scalar fitness
%   - u_cl   : optimized with CL term in scalar fitness

    % ----- Paper-aligned objective params -----
    params = oracle_make_params('alpha',0.9,'kappa_sf',0.0, ...
                               'beta_J',1.0,'beta_el',1.0,'beta_cmp',1.0);

    % No-risk weights: ignore f3 (CVaR) in scalar fitness
    w_nocl = [1.0, 1.0, 0.0];  % [f1, f2, f3]

    % With-risk weights: CVaR matters
    w_cl   = [1.0, 1.0, 3.0];

    % PSO options
    R   = scenarios(1).R;
    dim = 2*R;
    lb  = 0.0;
    ub  = 1.0;

    opts = struct();
    opts.num_particles = 30;
    opts.max_iter      = 80;
    opts.w_inertia     = 0.7;
    opts.c1            = 1.5;
    opts.c2            = 1.5;

    % ---- No-CL optimization ----
    fitness_nocl = @(u) scalar_fitness(u, scenarios, params, w_nocl);
    [u_nocl, F_nocl, hist_nocl] = pso_minimize_ma_kalman(fitness_nocl, dim, lb, ub, opts);
    [f1_nocl, f2_nocl, f3_nocl, det_nocl] = eval_objectives_CVaR(u_nocl, scenarios, params);

    % ---- With-CL optimization ----
    fitness_cl = @(u) scalar_fitness(u, scenarios, params, w_cl);
    [u_cl, F_cl, hist_cl] = pso_minimize_ma_kalman(fitness_cl, dim, lb, ub, opts);
    [f1_cl, f2_cl, f3_cl, det_cl] = eval_objectives_CVaR(u_cl, scenarios, params);

    % Pack results
    results.params    = params;

    results.u_nocl    = u_nocl;
    results.F_nocl    = F_nocl;
    results.f1_nocl   = f1_nocl;
    results.f2_nocl   = f2_nocl;
    results.f3_nocl   = f3_nocl;
    results.det_nocl  = det_nocl;
    results.hist_nocl = hist_nocl;

    results.u_cl      = u_cl;
    results.F_cl      = F_cl;
    results.f1_cl     = f1_cl;
    results.f2_cl     = f2_cl;
    results.f3_cl     = f3_cl;
    results.det_cl    = det_cl;
    results.hist_cl   = hist_cl;
end
