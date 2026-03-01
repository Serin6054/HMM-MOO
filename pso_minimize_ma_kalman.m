function [gbest_u, gbest_F, history] = pso_minimize_ma_kalman( ...
    fitness_fun, dim, lb, ub, opts)
% PSO_MINIMIZE_MA_KALMAN
%   Multi-agent Kalman PSO for EVA quota control.
%
%   [gbest_u, gbest_F, history] = pso_minimize_ma_kalman( ...
%       fitness_fun, dim, lb, ub, opts)
%
%   Same interface as pso_minimize, but:
%     - Uses a *filtered* global best (Kalman per agent)
%       instead of raw gbest.
%     - Treats the decision vector as concatenated agents:
%           u = [u_ch1 u_cp1 u_ch2 u_cp2 ...]
%
%   fitness_fun(u_row)    : handle, returns scalar
%   dim                   : dimension of u
%   lb, ub                : scalar or 1 x dim
%   opts                  : struct, with fields:
%       % Standard PSO (same names as pso_minimize)
%       .num_particles
%       .max_iter
%       .w_inertia
%       .c1, .c2
%
%       % Multi-agent / Kalman extras (all optional)
%       .agent_dim   : per-agent dimension (default 2)
%       .Q_scale     : process noise scale (default 1e-4)
%       .R_scale     : measurement noise scale (default 1e-2)
%       .P0          : initial covariance scale (default 1e-1)
%       .v_max       : (optional) scalar or 1 x dim velocity limit
%       .verbose     : (default true)
%
%   history.gbest_F(t) : best scalar fitness per iteration
%   (You can extend history as needed.)

    % ----------------- handle bounds & defaults ----------------- %
    if isscalar(lb)
        lb = lb * ones(1, dim);
    end
    if isscalar(ub)
        ub = ub * ones(1, dim);
    end

    % Standard PSO parameters (keep your naming)
    if ~isfield(opts, 'num_particles'), opts.num_particles = 40; end
    if ~isfield(opts, 'max_iter'),      opts.max_iter      = 200; end
    if ~isfield(opts, 'w_inertia'),     opts.w_inertia     = 0.7; end
    if ~isfield(opts, 'c1'),           opts.c1            = 1.5; end
    if ~isfield(opts, 'c2'),           opts.c2            = 1.5; end

    Np = opts.num_particles;
    Tm = opts.max_iter;
    w  = opts.w_inertia;
    c1 = opts.c1;
    c2 = opts.c2;

    % Multi-agent / Kalman defaults
    if ~isfield(opts, 'agent_dim'), opts.agent_dim = 2; end
    if ~isfield(opts, 'Q_scale'),   opts.Q_scale   = 1e-4; end
    if ~isfield(opts, 'R_scale'),   opts.R_scale   = 1e-2; end
    if ~isfield(opts, 'P0'),        opts.P0        = 1e-1; end
    if ~isfield(opts, 'verbose'),   opts.verbose   = true; end

    agent_dim = opts.agent_dim;

    if mod(dim, agent_dim) ~= 0
        error('pso_minimize_ma_kalman: dim=%d is not multiple of agent_dim=%d', ...
              dim, agent_dim);
    end
    n_agents = dim / agent_dim;

    % Kalman matrices (same for all agents)
    Q = opts.Q_scale * eye(agent_dim);
    R = opts.R_scale * eye(agent_dim);

    % Velocity limit (optional)
    have_vmax = isfield(opts, 'v_max') && ~isempty(opts.v_max);
    if have_vmax
        v_max = opts.v_max;
        if isscalar(v_max)
            v_max = v_max * ones(1, dim);
        else
            v_max = v_max(:).';
        end
    end

    % ----------------- initialize swarm ------------------------- %
    X = rand(Np, dim) .* (ub - lb) + lb;  % positions
    V = zeros(Np, dim);                   % velocities

    pbest_X = X;                          % personal bests
    pbest_F = inf(Np, 1);

    gbest_u = zeros(1, dim);
    gbest_F = inf;

    history.gbest_F = zeros(Tm, 1);

    % Evaluate initial population
    for i = 1:Np
        F_i      = fitness_fun(X(i,:));
        pbest_F(i) = F_i;

        if F_i < gbest_F
            gbest_F = F_i;
            gbest_u = X(i,:);
        end
    end

    history.gbest_F(1) = gbest_F;

    % ----------------- initialize Kalman states ----------------- %
    % agent_z(:,r) = 2x1 state for agent r
    agent_z = zeros(agent_dim, n_agents);
    P       = zeros(agent_dim, agent_dim, n_agents);

    for r = 1:n_agents
        idxs = (r-1)*agent_dim + (1:agent_dim);
        agent_z(:, r) = gbest_u(idxs).';         % initial estimate = gbest slice
        P(:,:,r)      = opts.P0 * eye(agent_dim);
    end

    % Build initial filtered global best Z_full
    Z_full = zeros(1, dim);
    for r = 1:n_agents
        idxs         = (r-1)*agent_dim + (1:agent_dim);
        Z_full(idxs) = agent_z(:, r).';
    end

    if opts.verbose
        fprintf('MA-Kalman PSO: dim=%d, agents=%d, Np=%d, iters=%d\n', ...
                dim, n_agents, Np, Tm);
        fprintf('Iter   Best_J\n');
        fprintf('%4d %9.4f\n', 1, gbest_F);
    end

    % ----------------- main PSO loop ---------------------------- %
    for t = 2:Tm
        for i = 1:Np
            % Update velocity: social term uses filtered Z_full, not raw gbest_u
            r1 = rand(1, dim);
            r2 = rand(1, dim);

            V(i,:) = w * V(i,:) ...
                   + c1 * r1 .* (pbest_X(i,:) - X(i,:)) ...
                   + c2 * r2 .* (Z_full       - X(i,:));

            if have_vmax
                V(i,:) = max(min(V(i,:),  v_max), -v_max);
            end

            % Update position
            X(i,:) = X(i,:) + V(i,:);

            % Clip to bounds
            X(i,:) = max(X(i,:), lb);
            X(i,:) = min(X(i,:), ub);

            % Evaluate
            F_i = fitness_fun(X(i,:));

            % Update personal best
            if F_i < pbest_F(i)
                pbest_F(i) = F_i;
                pbest_X(i,:) = X(i,:);
            end

            % Update global best (raw)
            if F_i < gbest_F
                gbest_F = F_i;
                gbest_u = X(i,:);
            end
        end

        % ------- Kalman update per agent using new gbest_u ------- %
        for r = 1:n_agents
            idxs  = (r-1)*agent_dim + (1:agent_dim);
            y     = gbest_u(idxs).';        % measurement (column)
            z_old = agent_z(:, r);
            P_old = P(:,:,r);

            % Prediction
            z_pred = z_old;
            P_pred = P_old + Q;

            % Kalman gain & update (H = I)
            K = P_pred / (P_pred + R);
            z_new = z_pred + K * (y - z_pred);
            P_new = (eye(agent_dim) - K) * P_pred;

            agent_z(:, r) = z_new;
            P(:,:,r)      = P_new;
        end

        % ------- build filtered global best Z_full for next iter - %
        for r = 1:n_agents
            idxs         = (r-1)*agent_dim + (1:agent_dim);
            Z_full(idxs) = agent_z(:, r).';
        end

        history.gbest_F(t) = gbest_F;

        if opts.verbose
            fprintf('%4d %9.4f\n', t, gbest_F);
        end
    end
end
