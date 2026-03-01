function u = solve_day_ahead_fixed(scens_design, params, opts)
%SOLVE_DAY_AHEAD_FIXED  Quantile-based fixed cap baseline (returns u length 2R).
%
% switches (optional):
%   switches.cvar     0/1  : if 0 -> median; if 1 -> alpha-quantile
%   switches.opf      0/1  : if 1 -> tighten electrical cap by factor (proxy OPF)
%   switches.coupled  0/1  : if 1 -> enforce joint cap P + gamma*F <= joint_quantile

    if nargin < 2, params = struct(); end
    if nargin < 3, opts = struct(); end
    if ~isfield(opts,'alpha')
        if isfield(params,'alpha')
            opts.alpha = params.alpha;
        else
            opts.alpha = 0.90;
        end
    end
    alpha = opts.alpha;

    switches = struct('cvar',1,'opf',0,'coupled',0);
    if isfield(opts,'switches') && isstruct(opts.switches)
        src = opts.switches;
    else
        % compatible with callers passing switches directly as opts
        src = opts;
    end
    fn = fieldnames(src);
    for i=1:numel(fn)
        if isfield(switches, fn{i})
            switches.(fn{i}) = src.(fn{i});
        end
    end

    % collect matrices
    S = numel(scens_design);
    assert(S>=1, 'Empty design scenario set.');

    P0 = scens_design(1).P_req_rt;
    [R,T] = size(P0);

    P_all = zeros(R, T, S);
    W_all = zeros(R, T, S);
    for s = 1:S
        P_all(:,:,s) = scens_design(s).P_req_rt;
        W_all(:,:,s) = scens_design(s).lambda_req_rt;
    end

    % choose quantile
    if switches.cvar == 0
        q = 0.50;
    else
        q = alpha;
    end

    % zone-wise quantile across time & scenarios
    P_cap = zeros(R,1);
    F_cap = zeros(R,1);
    for r = 1:R
        pvec = reshape(P_all(r,:,:), 1, []);
        wvec = reshape(W_all(r,:,:), 1, []);
        P_cap(r) = quantile(pvec, q);
        F_cap(r) = quantile(wvec, q);
    end

    % proxy OPF tightening: reduce EV caps a bit
    if switches.opf == 1
        if ~isfield(params,'opf_tighten'), params.opf_tighten = 0.90; end
        P_cap = params.opf_tighten * P_cap;
    end

    % coupled joint cap (proxy): P + gamma*F <= joint_quantile
    if switches.coupled == 1
        if ~isfield(params,'gamma_cp2kw'), params.gamma_cp2kw = 0.02; end
        gamma = params.gamma_cp2kw;

        joint_cap = zeros(R,1);
        for r = 1:R
            dvec = reshape(P_all(r,:,:),1,[]) + gamma * reshape(W_all(r,:,:),1,[]);
            joint_cap(r) = quantile(dvec, q);
        end

        % scale down (P,F) if violating joint cap
        for r = 1:R
            if P_cap(r) + gamma*F_cap(r) > joint_cap(r) && (P_cap(r) + gamma*F_cap(r))>0
                scale = joint_cap(r) / (P_cap(r) + gamma*F_cap(r));
                P_cap(r) = scale * P_cap(r);
                F_cap(r) = scale * F_cap(r);
            end
        end
    end

    % EXP-U-SCALE: optional quota output mode for unified u semantics.
    quota_mode = true;
    if isfield(params,'u_mode')
        quota_mode = strcmpi(string(params.u_mode), "quota");
    elseif isfield(params,'u_quota_mode')
        quota_mode = logical(params.u_quota_mode);
    end

    if quota_mode && isfield(scens_design(1),'Pmax') && isfield(scens_design(1),'Fcap')
        Pmax = max(scens_design(1).Pmax(:), 1e-9);
        Fcap = max(scens_design(1).Fcap(:), 1e-9);
        u = [min(max(P_cap ./ Pmax, 0), 1); min(max(F_cap ./ Fcap, 0), 1)];
    else
        u = [P_cap; F_cap];
    end
end
