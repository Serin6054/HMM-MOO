function results = exp_risk_aware_vs_neutral(scenarios)
% EXP_RISK_AWARE_VS_NEUTRAL  Run PSO twice: risk-neutral vs risk-aware.

    % ----- Paper-aligned objective params -----
    params = oracle_make_params('alpha',0.9,'kappa_sf',0.0, ...
                               'beta_J',1.0,'beta_el',1.0,'beta_cmp',1.0);

    % Scalar weights for [f1,f2,f3]
    w_rn = [1.0, 1.0, 0.0]; % risk-neutral (ignore CVaR)
    w_ra = [1.0, 1.0, 5.0]; % risk-aware

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

    % ---- Risk-neutral ----
    fitness_rn = @(u) scalar_fitness(u, scenarios, params, w_rn);
    [u_rn, F_rn, hist_rn] = pso_minimize_ma_kalman(fitness_rn, dim, lb, ub, opts);
    [f1_rn, f2_rn, f3_rn, det_rn] = eval_objectives_CVaR(u_rn, scenarios, params);

    % ---- Risk-aware ----
    fitness_ra = @(u) scalar_fitness(u, scenarios, params, w_ra);
    [u_ra, F_ra, hist_ra] = pso_minimize_ma_kalman(fitness_ra, dim, lb, ub, opts);
    [f1_ra, f2_ra, f3_ra, det_ra] = eval_objectives_CVaR(u_ra, scenarios, params);

    % Pack results
    results.params  = params;

    results.u_rn    = u_rn;
    results.F_rn    = F_rn;
    results.f1_rn   = f1_rn;
    results.f2_rn   = f2_rn;
    results.f3_rn   = f3_rn;
    results.det_rn  = det_rn;
    results.hist_rn = hist_rn;

    results.u_ra    = u_ra;
    results.F_ra    = F_ra;
    results.f1_ra   = f1_ra;
    results.f2_ra   = f2_ra;
    results.f3_ra   = f3_ra;
    results.det_ra  = det_ra;
    results.hist_ra = hist_ra;
end
