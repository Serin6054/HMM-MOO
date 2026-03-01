function tbl = exp_define_cases(case_list)
%EXP_DEFINE_CASES Build case-matrix table (Table 2).

if nargin < 1 || isempty(case_list)
    case_list = {'C1','C2','C3','C4','C5'};
end

n = numel(case_list);
case_id = strings(n,1);
case_name = strings(n,1);

coupled = false(n,1);
cvar = false(n,1);
opf = false(n,1);
ma_pso = false(n,1);
kalman = false(n,1);
va = false(n,1);
two_stage = false(n,1);

% placeholders (not implemented yet)
use_vfc = false(n,1);
use_reserve = false(n,1);
use_idl_mig = false(n,1);
notes = repmat("not implemented yet", n, 1);

for i = 1:n
    cid = upper(string(case_list{i}));
    sw = local_get_case_switches(cid);

    case_id(i) = cid;
    case_name(i) = local_case_name(cid);

    coupled(i) = logical(sw.coupled);
    cvar(i) = logical(sw.cvar);
    opf(i) = logical(sw.opf);
    ma_pso(i) = logical(sw.ma_pso);
    kalman(i) = logical(sw.kalman);
    va(i) = logical(sw.va);
    two_stage(i) = logical(sw.two_stage);
end

tbl = table(case_id, case_name, coupled, cvar, opf, ma_pso, kalman, va, two_stage, ...
            use_vfc, use_reserve, use_idl_mig, notes);
end

function sw = local_get_case_switches(case_id)
if exist('get_case_switches', 'file') == 2
    sw = get_case_switches(case_id);
elseif exist('utils.get_case_switches', 'file') == 2
    sw = feval('utils.get_case_switches', case_id);
else
    error('Cannot locate get_case_switches.m');
end
end

function name = local_case_name(case_id)
switch upper(string(case_id))
    case "C1"
        name = "Baseline";
    case "C2"
        name = "+Coupling";
    case "C3"
        name = "+CVaR";
    case "C4"
        name = "+OPF";
    case "C5"
        name = "Full(Proposed)";
    otherwise
        name = "Custom";
end
end
