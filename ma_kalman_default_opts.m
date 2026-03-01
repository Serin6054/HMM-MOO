function opts = ma_kalman_default_opts()
% MA_KALMAN_DEFAULT_OPTS  Default options for pso_minimize_ma_kalman.

    opts.num_particles = 40;
    opts.max_iter      = 150;

    opts.w_inertia     = 0.7;
    opts.c1            = 1.5;
    opts.c2            = 1.5;

    % Each EVA: [u_ch, u_cp]
    opts.agent_dim     = 2;

    % Kalman parameters
    opts.Q_scale       = 1e-4;
    opts.R_scale       = 1e-2;
    opts.P0            = 1e-1;

    % Optional velocity limit, comment out or change as needed
    % opts.v_max       = 0.2;
    opts.v_max         = [];

    opts.verbose       = true;
end
