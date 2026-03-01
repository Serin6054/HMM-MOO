function oracle_kappaF_noop_check(cache_path)
%ORACLE_KAPPAF_NOOP_CHECK  Minimal, reviewer-proof check that κ_F scaling affects oracle outputs.
%
% Usage:
%   oracle_kappaF_noop_check
%   oracle_kappaF_noop_check('./cache/scenarios.mat')
%
% Requires your codebase functions:
%   oracle_make_params, oracle_eval
%
% It prints:
%   - what fields were actually scaled
%   - f1/f3 comparison between kappaF=0.6 and 1.4
% -------------------------------------------------------------------------

    if nargin < 1 || isempty(cache_path)
        cache_path = './cache/scenarios.mat';
    end

    if exist(cache_path,'file') ~= 2
        error('oracle_kappaF_noop_check:MissingFile', 'Cannot find %s', cache_path);
    end

    S = load(cache_path, 'scenarios');
    if ~isfield(S,'scenarios')
        error('oracle_kappaF_noop_check:NoScenarios', 'File does not contain variable ''scenarios''.');
    end
    scenarios = S.scenarios;

    if exist('oracle_make_params','file') ~= 2
        error('oracle_kappaF_noop_check:MissingOracle', 'oracle_make_params.m not found on MATLAB path.');
    end
    if exist('oracle_eval','file') ~= 2
        error('oracle_kappaF_noop_check:MissingOracle', 'oracle_eval.m not found on MATLAB path.');
    end

    params = oracle_make_params('eval.mode',"full",'eval.seed',2025);

    R = scenarios(1).R;
    dim = 2*R;
    u = 0.5*ones(1,dim);

    [sc06, p06, info06] = apply_compute_capacity_scale(scenarios, params, 0.6, R, struct('strict', false));
    [sc14, p14, info14] = apply_compute_capacity_scale(scenarios, params, 1.4, R, struct('strict', false));

    disp(info06); disp(info14);

    out06 = oracle_eval(u, sc06, p06, 1:20);
    out14 = oracle_eval(u, sc14, p14, 1:20);

    fprintf("f3: %.6g -> %.6g\n", out06.f3, out14.f3);
    fprintf("f1: %.6g -> %.6g\n", out06.f1, out14.f1);
    fprintf("Note: edge power affects f1 only if your oracle includes P_edge in electrical cost.\n");
end
