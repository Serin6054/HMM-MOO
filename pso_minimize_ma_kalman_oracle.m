function [gbest_u, gbest_F, history] = pso_minimize_ma_kalman_oracle(scenarios, params, dim, lb, ub, opts)
%PSO_MINIMIZE_MA_KALMAN_ORACLE  MA-Kalman PSO with CRN scenario batching per iteration.

if isscalar(lb), lb = lb*ones(1,dim); end
if isscalar(ub), ub = ub*ones(1,dim); end

if ~isfield(opts,'agent_dim'), opts.agent_dim = 2; end
if ~isfield(opts,'Q_scale'),   opts.Q_scale   = 1e-4; end
if ~isfield(opts,'R_scale'),   opts.R_scale   = 1e-2; end
if ~isfield(opts,'P0'),        opts.P0        = 1e-1; end
if ~isfield(opts,'verbose'),   opts.verbose   = true; end

agent_dim = opts.agent_dim;
if mod(dim,agent_dim)~=0
    error('dim must be multiple of agent_dim.');
end
n_agents = dim/agent_dim;

Q = opts.Q_scale*eye(agent_dim);
R = opts.R_scale*eye(agent_dim);

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

% ----- init with iteration-1 batch -----
omega_idx = oracle_get_batch(1, S, params);

for i=1:Np
    out = oracle_eval(X(i,:), scenarios, params, omega_idx);
    F_i = out.fitness;
    pbest_F(i) = F_i;
    if F_i < gbest_F
        gbest_F = F_i;
        gbest_u = X(i,:);
    end
end
history.gbest_F(1) = gbest_F;

% ----- Kalman init -----
agent_z = zeros(agent_dim, n_agents);
P       = zeros(agent_dim, agent_dim, n_agents);

for r=1:n_agents
    idxs = (r-1)*agent_dim + (1:agent_dim);
    agent_z(:,r) = gbest_u(idxs).';
    P(:,:,r)     = opts.P0*eye(agent_dim);
end

Z_full = zeros(1,dim);
for r=1:n_agents
    idxs = (r-1)*agent_dim + (1:agent_dim);
    Z_full(idxs) = agent_z(:,r).';
end

if opts.verbose
    fprintf('MA-Kalman(oracle): dim=%d agents=%d Np=%d iters=%d\n', dim, n_agents, Np, Tm);
    fprintf('Iter   Best_J\n%4d %9.4f\n', 1, gbest_F);
end

% ----- main loop -----
for t=2:Tm
    omega_idx = oracle_get_batch(t, S, params); % CRN for this iteration

    for i=1:Np
        r1 = rand(1,dim); r2 = rand(1,dim);
        V(i,:) = w*V(i,:) ...
               + c1*r1.*(pbest_X(i,:)-X(i,:)) ...
               + c2*r2.*(Z_full - X(i,:));

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

    % Kalman update per agent using gbest_u
    for r=1:n_agents
        idxs  = (r-1)*agent_dim + (1:agent_dim);
        y     = gbest_u(idxs).';
        z_old = agent_z(:,r);
        P_old = P(:,:,r);

        z_pred = z_old;
        P_pred = P_old + Q;

        K = P_pred / (P_pred + R);
        z_new = z_pred + K*(y - z_pred);
        P_new = (eye(agent_dim)-K)*P_pred;

        agent_z(:,r) = z_new;
        P(:,:,r)     = P_new;
    end

    for r=1:n_agents
        idxs = (r-1)*agent_dim + (1:agent_dim);
        Z_full(idxs) = agent_z(:,r).';
    end

    history.gbest_F(t) = gbest_F;

    if opts.verbose
        fprintf('%4d %9.4f\n', t, gbest_F);
    end
end
end
