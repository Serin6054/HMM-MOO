function [s_ev, s_cp] = compute_inverse_shapes_from_design(sc_design, clip_lo, clip_hi, gamma)
% Build inverse-demand diurnal shapes from design scenarios.
% Output: s_ev, s_cp are 1xT vectors, normalized to mean=1, clipped.
% gamma > 1 increases diurnal contrast.

    if nargin < 2 || isempty(clip_lo), clip_lo = 0.3; end
    if nargin < 3 || isempty(clip_hi), clip_hi = 3.0; end
    if nargin < 4 || isempty(gamma),   gamma   = 2.0; end

    S = numel(sc_design);
    assert(S >= 1, 'Empty design scenario set.');

    assert(isfield(sc_design(1),'P_req_rt'), 'design scenarios missing P_req_rt');
    assert(isfield(sc_design(1),'lambda_req_rt'), 'design scenarios missing lambda_req_rt');

    [R,T] = size(sc_design(1).P_req_rt);

    p_sum = zeros(1,T);
    w_sum = zeros(1,T);

    for s = 1:S
        P = sc_design(s).P_req_rt;          % [R x T]
        W = sc_design(s).lambda_req_rt;     % [R x T]
        p_sum = p_sum + sum(P, 1);
        w_sum = w_sum + sum(W, 1);
    end

    p_bar = p_sum / (S * R);
    w_bar = w_sum / (S * R);

    eps0 = 1e-6;
    s_ev = ((mean(p_bar) + eps0) ./ (p_bar + eps0)).^gamma;
    s_cp = ((mean(w_bar) + eps0) ./ (w_bar + eps0)).^gamma;

    % Normalize mean to 1
    s_ev = s_ev / mean(s_ev);
    s_cp = s_cp / mean(s_cp);

    % Clip and renormalize
    s_ev = min(max(s_ev, clip_lo), clip_hi);
    s_cp = min(max(s_cp, clip_lo), clip_hi);
    s_ev = s_ev / mean(s_ev);
    s_cp = s_cp / mean(s_cp);
end