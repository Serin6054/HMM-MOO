function [best_u, best_F, history] = pso_minimize_ma_kalman_va_oracle( ...
    scenarios, params, dim, lb, ub, opts)
%PSO_MINIMIZE_MA_KALMAN_VA_ORACLE
% Multi-agent PSO (block-wise) with optional:
%   (i) Kalman smoothing on the broadcast best position (Kalman-pos)
%   (ii) Vector Adaptation (VA) term added to velocity
%   (iii) Optional Kalman smoothing on each particle's fitness for VA signal (Kalman-fit)
%
% Required:
%   - oracle_get_batch(iter_k, S, params)
%   - oracle_eval(u, scenarios, params, omega_idx)
%
% Key options in opts:
%   opts.agent_dim (default 2)
%   opts.use_kalman_pos (true/false)
%   opts.use_va (true/false)
%   opts.use_kalman_fit (true/false)  % only affects VA signal stability
%
%   PSO: opts.num_particles, opts.max_iter, opts.w_inertia, opts.c1, opts.c2
%   Kalman-pos: opts.Q_pos, opts.R_pos, opts.P0_pos (scalar or matrix per agent_dim)
%   VA: opts.beta_va, opts.gamma_va, opts.eps_va
%   Kalman-fit: opts.Q_fit, opts.R_fit, opts.P0_fit  (scalar)
%
% Output:
%   best_u, best_F
%   history.best_F (per iteration)
%   history.best_u (optional snapshots can be added)

% ---------------- defaults ----------------
if ~isfield(opts,'agent_dim'),        opts.agent_dim = 2; end
if ~isfield(opts,'use_kalman_pos'),   opts.use_kalman_pos = true; end
if ~isfield(opts,'use_va'),           opts.use_va = true; end
if ~isfield(opts,'use_kalman_fit'),   opts.use_kalman_fit = true; end

if ~isfield(opts,'num_particles'),    opts.num_particles = 30; end
if ~isfield(opts,'max_iter'),         opts.max_iter = 80; end
if ~isfield(opts,'w_inertia'),        opts.w_inertia = 0.7; end
if ~isfield(opts,'c1'),               opts.c1 = 1.5; end
if ~isfield(opts,'c2'),               opts.c2 = 1.5; end

% Kalman-pos (per agent block)
if ~isfield(opts,'Q_pos'),            opts.Q_pos = 1e-4; end
if ~isfield(opts,'R_pos'),            opts.R_pos = 1e-2; end
if ~isfield(opts,'P0_pos'),           opts.P0_pos = 1e-1; end

% VA
if ~isfield(opts,'beta_va'),          opts.beta_va = 0.85; end  % memory
if ~isfield(opts,'gamma_va'),         opts.gamma_va = 0.15; end % strength
if ~isfield(opts,'eps_va'),           opts.eps_va = 1e-9; end

% Kalman-fit (scalar per particle)
if ~isfield(opts,'Q_fit'),            opts.Q_fit = 1e-4; end
if ~isfield(opts,'R_fit'),            opts.R_fit = 5e-3; end
if ~isfield(opts,'P0_fit'),           opts.P0_fit = 1e-1; end

if ~isfield(opts,'verbose'),          opts.verbose = true; end
% --- FULL必须：Kalman-fit用于“选择”(pbest/gbest)，而不仅仅是VA信号 ---
if ~isfield(opts,'use_kalman_fit_for_selection'), opts.use_kalman_fit_for_selection = true; end
if ~isfield(opts,'feasible_only_update'),         opts.feasible_only_update = true; end
if ~isfield(opts,'dJ_clip'),                      opts.dJ_clip = 0.25; end


% Infeasibility handling for Kalman-fit stability (paper protocol)
% When oracle reports flaginf=1, the penalty-dominated sample can destabilize
% the Kalman-fit update used by VA. Choose:
%   - "skip": skip Kalman-fit update (dJ=0 for this step)
%   - "clip": clip the fitness observation before Kalman update
if ~isfield(opts,'infeas_kalman_action'), opts.infeas_kalman_action = "skip"; end
if ~isfield(opts,'infeas_clip_value'),    opts.infeas_clip_value = 1e6; end

if ~isfield(opts,'use_fit_ucb'), opts.use_fit_ucb = true; end
if ~isfield(opts,'fit_ucb_k'),   opts.fit_ucb_k   = 0.5;  end

if ~isfield(opts,'kalman_pos_mix'), opts.kalman_pos_mix = 0.2; end


% --------------- checks & shapes ---------------
if isscalar(lb), lb = lb*ones(1,dim); end
if isscalar(ub), ub = ub*ones(1,dim); end

agent_dim = opts.agent_dim;
if mod(dim,agent_dim)~=0
    error('dim must be multiple of agent_dim.');
end
n_agents = dim/agent_dim;

Np = opts.num_particles;
Tm = opts.max_iter;
w  = opts.w_inertia; c1=opts.c1; c2=opts.c2;

S = numel(scenarios);

% --------------- init swarm ---------------
X = rand(Np, dim).*(ub-lb) + lb;
V = zeros(Np, dim);

pbest_X = X;
pbest_F = inf(Np,1);

A = zeros(Np, dim);  % VA adaptation vector per particle

% ---- init best using iteration-1 CRN batch ----
omega_idx = oracle_get_batch(1, S, params);

best_u = zeros(1,dim);
best_F = inf;

for i=1:Np
    out = oracle_eval(X(i,:), scenarios, params, omega_idx);
    Fi = out.fitness;
    pbest_F(i) = Fi;

    if Fi < best_F
        best_F = Fi;
        best_u = X(i,:);
    end
end

% --------------- Kalman-pos state (optional) ---------------
% It smooths the broadcast best position block-by-block.
Z_pos = best_u; % smoothed/broadcast position
if opts.use_kalman_pos
    Qp = opts.Q_pos; Rp = opts.R_pos; P0p = opts.P0_pos;

    % Store per-agent state as vector + covariance
    z_agent = zeros(agent_dim, n_agents);
    P_agent = zeros(agent_dim, agent_dim, n_agents);

    for r=1:n_agents
        idx = (r-1)*agent_dim + (1:agent_dim);
        z_agent(:,r) = best_u(idx).';
        P_agent(:,:,r) = P0p*eye(agent_dim);
    end
end

% --------------- Kalman-fit state (optional for VA signal) ---------------
% Smooth each particle's scalar fitness observation.
if opts.use_kalman_fit
    Jhat = pbest_F;                % initial smoothed fitness
    Pfit = opts.P0_fit*ones(Np,1); % error variance
end

% --------------- history ---------------
history.best_F = zeros(Tm,1);
history.best_F(1) = best_F;

if opts.verbose
    fprintf('MA-PSO (oracle): agents=%d, dim=%d, Np=%d, iters=%d\n', n_agents, dim, Np, Tm);
    fprintf('  use_kalman_pos=%d, use_va=%d, use_kalman_fit=%d\n', ...
        opts.use_kalman_pos, opts.use_va, opts.use_kalman_fit);
    fprintf('Iter   Best_F\n%4d %10.4f\n', 1, best_F);
end

% ================= MAIN LOOP =================
for t=2:Tm
    omega_idx = oracle_get_batch(t, S, params); % CRN batch for iteration t

    % define the attractor used in PSO term
    if opts.use_kalman_pos
        attractor = Z_pos;
    else
        attractor = best_u;
    end

    % one iteration
    for i=1:Np
        % ---- evaluate current particle for VA signal (needs previous fitness) ----
        if opts.use_va
            if opts.use_kalman_fit
                J_prev = Jhat(i);
                P_prev = Pfit(i);
            else
                % raw fitness as signal (store last raw value locally)
                if t==2
                    J_prev = pbest_F(i); % fallback
                else
                    J_prev = history.particle_lastF(i);
                end
            end
        end

        % ---- canonical PSO update ----
        r1 = rand(1,dim); r2 = rand(1,dim);
        V_std = w*V(i,:) ...
              + c1*r1.*(pbest_X(i,:) - X(i,:)) ...
              + c2*r2.*(attractor  - X(i,:));        % ---- VA update (optional) ----
        if opts.use_va
            % Evaluate candidate position after the *standard* PSO move (V_std),
            % then use the observed improvement to update VA. VA affects the
            % stored velocity (thus next-step inertia) while keeping evaluation
            % cost at one oracle call per particle.
            V_temp = V_std;
            X_temp = X(i,:) + V_temp;
            X_temp = max(min(X_temp, ub), lb);

            out_temp = oracle_eval(X_temp, scenarios, params, omega_idx);
            Fi = out_temp.fitness;

            % --- Kalman-fit (scalar) to stabilize the improvement signal ---
            if opts.use_kalman_fit
                J_prev = Jhat(i);
                P_prev = Pfit(i);

                if (isfield(out_temp,'flaginf') && out_temp.flaginf==1)
                    action = opts.infeas_kalman_action;
                    if strcmp(action,"skip")
                        dJ = 0;
                        % keep Jhat/Pfit unchanged
                    elseif strcmp(action,"clip")
                        F_obs = min(Fi, opts.infeas_clip_value);
                        Qf = opts.Q_fit; Rf = opts.R_fit;

                        J_pred = J_prev;
                        P_pred = P_prev + Qf;
                        K = P_pred / (P_pred + Rf);
                        J_new = J_pred + K*(F_obs - J_pred);
                        P_new = (1-K)*P_pred;

                        dJ = J_prev - J_new;
                        Jhat(i) = J_new;
                        Pfit(i) = P_new;
                    else
                        error('Unknown opts.infeas_kalman_action=%s', action);
                    end
                else
                    Qf = opts.Q_fit; Rf = opts.R_fit;

                    J_pred = J_prev;
                    P_pred = P_prev + Qf;
                    K = P_pred / (P_pred + Rf);
                    J_new = J_pred + K*(Fi - J_pred);
                    P_new = (1-K)*P_pred;

                    dJ = J_prev - J_new;
                    Jhat(i) = J_new;
                    Pfit(i) = P_new;
                end
            else
                % no Kalman-fit: use raw improvement w.r.t. previous observed fitness
                if t==2 && isinf(pbest_F(i))
                    J_prev = Fi; % initialize
                    dJ = 0;
                else
                    if isfield(history,'particle_lastF') && numel(history.particle_lastF)>=i && history.particle_lastF(i)>0
                        J_prev = history.particle_lastF(i);
                    else
                        J_prev = Fi;
                    end
                    dJ = J_prev - Fi;
                end
            end

            if ~isfield(history,'particle_lastF')
                history.particle_lastF = zeros(Np,1);
            end
            history.particle_lastF(i) = Fi;

            % Direction relative to personal best
            d = X_temp - pbest_X(i,:);
            dn = norm(d) + opts.eps_va;

            % ---- scale-free VA signal ----
            dJ_norm = dJ / (abs(J_prev) + opts.eps_va);
            dJ_norm = max(min(dJ_norm, opts.dJ_clip), -opts.dJ_clip);

            A(i,:) = opts.beta_va*A(i,:) + (1-opts.beta_va)*dJ_norm*(d/dn);
            V(i,:) = V_std + opts.gamma_va*A(i,:);

            % commit new position
            X(i,:) = X_temp;

            is_infeas = ( (isfield(out_temp,'flaginf') && out_temp.flaginf==1) || ...
                          (isfield(out_temp,'infeas_rate') && out_temp.infeas_rate>0) );

            % selection fitness: always keep penalty for infeasible; use Kalman-fit only when feasible
            Fi_sel = Fi;
            if opts.use_kalman_fit && opts.use_kalman_fit_for_selection && ~is_infeas
                Fi_sel = min(Jhat(i), Fi);
            end

        else
            % No VA: standard PSO move + evaluate
            V(i,:) = V_std;
            X(i,:) = X(i,:) + V(i,:);
            X(i,:) = max(min(X(i,:), ub), lb);

            out = oracle_eval(X(i,:), scenarios, params, omega_idx);
            Fi  = out.fitness;

            is_infeas = ( (isfield(out,'flaginf') && out.flaginf==1) || ...
                          (isfield(out,'infeas_rate') && out.infeas_rate>0) );

            Fi_sel = Fi; % no Kalman-fit update in this branch
        end

        % ---- update personal best (可行解优先) ----
        if (~opts.feasible_only_update || ~is_infeas) && (Fi_sel < pbest_F(i))
            pbest_F(i)  = Fi_sel;
            pbest_X(i,:) = X(i,:);
        end
        
        % ---- update global best (可行解优先) ----
        if (~opts.feasible_only_update || ~is_infeas) && (Fi_sel < best_F)
            best_F = Fi_sel;
            best_u = X(i,:);
        end


    end

    % ---- Kalman-pos update using best_u (optional) ----
    if opts.use_kalman_pos
        % update each agent block
        for r=1:n_agents
            idx = (r-1)*agent_dim + (1:agent_dim);

            y = best_u(idx).';     % measurement: best position block
            z = z_agent(:,r);      % prior state
            Pm = P_agent(:,:,r);

            % model: random walk
            z_pred = z;
            P_pred = Pm + opts.Q_pos*eye(agent_dim);

            K = P_pred / (P_pred + opts.R_pos*eye(agent_dim));
            z_new = z_pred + K*(y - z_pred);
            P_new = (eye(agent_dim)-K)*P_pred;

            z_agent(:,r) = z_new;
            P_agent(:,:,r) = P_new;

            Z_pos(idx) = (1-opts.kalman_pos_mix)*y.' + opts.kalman_pos_mix*z_new.';
        end
    end

    history.best_F(t) = best_F;

    if opts.verbose
        fprintf('%4d %10.4f\n', t, best_F);
    end
end
end