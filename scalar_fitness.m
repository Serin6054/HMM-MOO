function F = scalar_fitness(u, scenarios, params, w)
% SCALAR_FITNESS  Scalar objective used by PSO.
%
%   F = scalar_fitness(u, scenarios, params, w)
%
%   w : [w1, w2, w3] weights for f1..f3

    [f1, f2, f3] = eval_objectives_CVaR(u, scenarios, params);
    F = w(1)*f1 + w(2)*f2 + w(3)*f3;
end
