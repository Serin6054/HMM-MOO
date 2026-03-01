function [f1,f2,f3,det] = eval_objectives_CVaR_plus(u, scenarios, params)
%EVAL_OBJECTIVES_CVAR_PLUS  Wrapper to fill missing det fields for reporting.

    [f1,f2,f3,det] = eval_objectives_CVaR(u, scenarios, params);

    % mean_cost: if the base evaluator does not provide it, use f1 as a proxy.
    if ~isfield(det,'mean_cost') || isempty(det.mean_cost) || ~isfinite(det.mean_cost)
        det.mean_cost = f1;
    end

    % feasible_rate: prefer evaluator's own field if it exists; otherwise proxy = 1.
    cand = {'feasible_rate','opf_feasible_rate','is_feasible_rate','feasible'};
    fr = NaN;
    for k = 1:numel(cand)
        if isfield(det,cand{k})
            v = det.(cand{k});
            if islogical(v) || isnumeric(v)
                if numel(v) > 1
                    fr = mean(double(v(:)));
                else
                    fr = double(v);
                end
                break;
            end
        end
    end
    if ~isfinite(fr)
        fr = 1.0;  % NOTE: OPF not wired here -> placeholder; later we replace by true OPF feasible ratio.
    end
    det.feasible_rate = fr;

    % Add some useful diagnostics for debugging
    try
        S = numel(scenarios);
        sumDW  = zeros(S,1);
        sumDP  = zeros(S,1);
        
        slackEV = zeros(S,1);
        slackCP = zeros(S,1);
        flag2S  = zeros(S,1);
        
        for s = 1:S
            m = sim_one_scenario(u, scenarios(s), params);
        
            % --- 你原来的统计 ---
            sumDW(s) = sum(m.debug.DeltaW(:));
            sumDP(s) = sum(m.debug.DeltaP_EV(:));
        
            % --- 诊断1：two_stage 是否真的生效 ---
            if isfield(m.debug,'two_stage')
                flag2S(s) = m.debug.two_stage;
            else
                % 如果你还没加 m.debug.two_stage，就先让它为 NaN
                flag2S(s) = NaN;
            end
        
            % --- 诊断2：是否存在 slack（cap > req 的时段）---
            if isfield(m.debug,'P_allow_rt') && isfield(m.debug,'P_EV_req')
                slackEV(s) = sum(max(m.debug.P_allow_rt(:) - m.debug.P_EV_req(:), 0));
            end
            if isfield(m.debug,'F_allow_rt') && isfield(m.debug,'lambda_req_rt')
                slackCP(s) = sum(max(m.debug.F_allow_rt(:) - m.debug.lambda_req_rt(:), 0));
            end
        end
        
        det.mean_DeltaW     = mean(sumDW);
        det.mean_DeltaP_EV  = mean(sumDP);
        
        det.frac_two_stage  = mean(flag2S==1);
        det.mean_slackEV    = mean(slackEV);
        det.mean_slackCP    = mean(slackCP);
    catch
        % no-op
    end
end