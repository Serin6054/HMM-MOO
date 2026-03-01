function baseline_results = run_baselines(scenarios, params)
% RUN_BASELINES  Evaluate a few simple quota baselines.
%
%   baseline_results.u_list   : K x D quota vectors
%   baseline_results.metrics  : struct with f1..f3 for each baseline

    R   = scenarios(1).R;
    dim = 2*R;

    % Baseline 1: fully open quotas
    u1 = [ones(1,R), ones(1,R)];

    % Baseline 2: uniform conservative quotas
    u2 = [0.7*ones(1,R), 0.7*ones(1,R)];

    % Baseline 3: demand-proportional quotas (based on average P_req)
    S = numel(scenarios);
    P_sum = zeros(R,1);
    T_sum = 0;
    for s = 1:S
        P_sum = P_sum + sum(scenarios(s).P_req_rt, 2);
        T_sum = T_sum + scenarios(s).T;
    end
    P_avg = P_sum / T_sum;       % average power per EVA
    if max(P_avg) > 0
        u3_ch = P_avg' / max(P_avg);
    else
        u3_ch = ones(1,R);
    end
    u3_cp = u3_ch;
    u3 = [u3_ch, u3_cp];

    U = [u1; u2; u3];
    K = size(U,1);

    f1 = zeros(K,1);
    f2 = zeros(K,1);
    f3 = zeros(K,1);
    % (paper has only 3 objectives)

    for k = 1:K
        [f1(k), f2(k), f3(k)] = eval_objectives_CVaR(U(k,:), scenarios, params);
    end

    metrics.f1 = f1;
    metrics.f2 = f2;
    metrics.f3 = f3;
    baseline_results.u_list  = U;
    baseline_results.metrics = metrics;
end
