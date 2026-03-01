function [u_best, scen_k, params_full_k] = a1_pick_best_solution(A1, method_name, kk, scenarios_base)
% Pick the seed with minimum full-set fitness for (method, kappa index kk).
% Also return the scaled scenario set and full-eval params used for that kappa.

% find variant index
vidx = [];
for v=1:numel(A1.variants)
    if A1.variants{v}.name == method_name
        vidx = v; break;
    end
end
if isempty(vidx)
    error('Method %s not found in A1.variants.', method_name);
end

cell_data = A1.data{vidx, kk};
Ecell = cell_data.full_eval;
E = [Ecell{:}];
fit = [E.fitness];
[~, sBest] = min(fit);
u_best = cell_data.bestU(sBest,:);

% reconstruct scaled scenarios/params_full consistently
% Determine whether method is RA or RN from name prefix
isRN = startsWith(method_name, "RN");
root_params_full = oracle_make_params('eval.mode',"full",'eval.B',30,'eval.K_resamp',1,'eval.seed',2025);
if isRN
    root_params_full = apply_risk_neutral(root_params_full);
end

kappaF = A1.kappa_list(kk);
[scen_k, params_full_k, ~] = apply_compute_capacity_scale(scenarios_base, root_params_full, kappaF, A1.R);
end
