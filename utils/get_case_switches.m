function sw = get_case_switches(case_id)
%GET_CASE_SWITCHES Return boolean switches for ablation case.
%
% Simplified 5-case ablation ladder:
%   C1 Baseline
%   C2 + Coupling
%   C3 + CVaR
%   C4 + OPF
%   C5 Full (Proposed: MA-PSO + KF + VA)
%
% Design choice:
% - two_stage is FIXED ON for all cases (not an ablation dimension here).

case_id = upper(string(case_id));

% defaults (all off)
sw = struct('two_stage',true,'coupled',false,'cvar',false,'opf',false,...
            'ma_pso',false,'kalman',false,'va',false);

switch case_id
    case "C1"
        % Baseline: only two-stage dynamics (fixed ON) without coupling/CVaR/OPF.
    case "C2"
        sw.coupled = true;
    case "C3"
        sw.coupled = true;
        sw.cvar    = true;
    case "C4"
        sw.coupled = true;
        sw.cvar    = true;
        sw.opf     = true;
    case {"C5","FULL"}
        sw.coupled = true;
        sw.cvar    = true;
        sw.opf     = true;
        sw.ma_pso  = true;
        sw.kalman  = true;
        sw.va      = true;
    otherwise
        error('Unknown case_id: %s', case_id);
end
end
