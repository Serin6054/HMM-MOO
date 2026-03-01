function p = apply_risk_neutral(params)
% Set the CVaR weight lambda_R to 0 (risk-neutral).
p = params;

cand = { ...
    {'lambda_R'}, {'lambdaR'}, {'lambda_r'}, ...
    {'lambdaRisk'}, {'lambda_cvar'}, {'lambda_CVaR'} ...
};

hit = false;
for i=1:numel(cand)
    f = cand{i}{1};
    if isfield(p,f)
        p.(f) = 0;
        hit = true;
    end
end

if ~hit
    warning(['apply_risk_neutral: did not find a lambda_R field. ', ...
             'Please add your oracle''s risk-weight field name here.']);
end
end
