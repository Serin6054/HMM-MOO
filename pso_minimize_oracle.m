function [gbest_u, gbest_F, history] = pso_minimize_oracle(scenarios, params, dim, lb, ub, opts)
%PSO_MINIMIZE_ORACLE  Standard PSO but scenario batch Omega_k fixed per iteration.

if isscalar(lb), lb = lb*ones(1,dim); end
if isscalar(ub), ub = ub*ones(1,dim); end

Np = opts.num_particles;
Tm = opts.max_iter;
w  = opts.w_inertia;
c1 = opts.c1;
c2 = opts.c2;

S = numel(scenarios);

X = rand(Np, dim).*(ub-lb) + lb;
V = zeros(Np, dim);

pbest_X = X;
pbest_F = inf(Np,1);

gbest_u = zeros(1,dim);
gbest_F = inf;

history.gbest_F = zeros(Tm,1);

% ---- iteration 1 batch ----
omega_idx = oracle_get_batch(1, S, params);

for i=1:Np
    out = oracle_eval(X(i,:), scenarios, params, omega_idx);
    F_i = out.fitness;
    pbest_F(i) = F_i;
    if F_i < gbest_F
        gbest_F = F_i; gbest_u = X(i,:);
    end
end
history.gbest_F(1) = gbest_F;

for t=2:Tm
    omega_idx = oracle_get_batch(t, S, params); % CRN batch for this iteration

    for i=1:Np
        r1 = rand(1,dim); r2 = rand(1,dim);
        V(i,:) = w*V(i,:) + c1*r1.*(pbest_X(i,:)-X(i,:)) + c2*r2.*(gbest_u-X(i,:));
        X(i,:) = X(i,:) + V(i,:);
        X(i,:) = max(min(X(i,:), ub), lb);

        out = oracle_eval(X(i,:), scenarios, params, omega_idx);
        F_i = out.fitness;

        if F_i < pbest_F(i)
            pbest_F(i) = F_i; pbest_X(i,:) = X(i,:);
        end
        if F_i < gbest_F
            gbest_F = F_i; gbest_u = X(i,:);
        end
    end
    history.gbest_F(t) = gbest_F;
end
end
