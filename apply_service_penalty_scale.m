function [p_opt, p_full] = apply_service_penalty_scale(params_opt_in, params_full_in, kappaSF)
%APPLY_SERVICE_PENALTY_SCALE  Scale charging-shortfall penalty κ_sf for A2.
%
% Paper definition: κ_sf appears inside the scenario-wise operating cost J(u,ω)
% via +κ_sf ΔP_EV. Scaling κ_sf therefore directly changes the service
% shortfall penalty while keeping the other objective weights unchanged.
%
% Usage:
%   [p_opt, p_full] = apply_service_penalty_scale(params_opt, params_full, kappaSF)

p_opt  = params_opt_in;
p_full = params_full_in;

if isfield(p_opt,'kappa_sf'),  p_opt.kappa_sf  = p_opt.kappa_sf  * kappaSF; else, p_opt.kappa_sf  = kappaSF; end
if isfield(p_full,'kappa_sf'), p_full.kappa_sf = p_full.kappa_sf * kappaSF; else, p_full.kappa_sf = kappaSF; end
end
