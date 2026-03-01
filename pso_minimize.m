function [gbest_u, gbest_F, history] = pso_minimize(fitness_fun, dim, lb, ub, opts)
% PSO_MINIMIZE  Simple PSO optimizer for box-constrained problem.
%
%   [gbest_u, gbest_F, history] = pso_minimize(fitness_fun, dim, lb, ub, opts)
%
%   fitness_fun : handle @(u) scalar_fitness(u,...)
%   dim         : dimension of control vector
%   lb, ub      : lower/upper bounds (scalar or 1 x dim)
%   opts        : struct with
%                 .num_particles
%                 .max_iter
%                 .w_inertia
%                 .c1, .c2
%
%   history     : struct with .gbest_F (best fitness per iteration)

    % Defaults
    if isscalar(lb)
        lb = lb * ones(1, dim);
    end
    if isscalar(ub)
        ub = ub * ones(1, dim);
    end

    Np = opts.num_particles;
    Tm = opts.max_iter;
    w  = opts.w_inertia;
    c1 = opts.c1;
    c2 = opts.c2;

    % Initialize
    X = rand(Np, dim) .* (ub - lb) + lb;  % positions
    V = zeros(Np, dim);                  % velocities

    pbest_X = X;                         % personal best positions
    pbest_F = inf(Np, 1);                % personal best fitness

    gbest_u = zeros(1, dim);
    gbest_F = inf;

    history.gbest_F = zeros(Tm, 1);

    % Evaluate initial population
    for i = 1:Np
        F_i = fitness_fun(X(i,:));
        pbest_F(i) = F_i;
        if F_i < gbest_F
            gbest_F = F_i;
            gbest_u = X(i,:);
        end
    end

    history.gbest_F(1) = gbest_F;

    % Main loop
    for t = 2:Tm
        for i = 1:Np
            % Update velocity
            r1 = rand(1, dim);
            r2 = rand(1, dim);
            V(i,:) = w * V(i,:) ...
                    + c1 * r1 .* (pbest_X(i,:) - X(i,:)) ...
                    + c2 * r2 .* (gbest_u       - X(i,:));

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

            % Update global best
            if F_i < gbest_F
                gbest_F = F_i;
                gbest_u = X(i,:);
            end
        end

        history.gbest_F(t) = gbest_F;
        % Optional: display iteration info
        % fprintf('Iter %3d | gbest_F = %.4f\n', t, gbest_F);
    end
end
