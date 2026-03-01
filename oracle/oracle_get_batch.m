function omega_idx = oracle_get_batch(iter_k, S, params)
%ORACLE_GET_BATCH  Return scenario indices Omega_k for iteration k
% without touching the global RNG used by PSO.

mode = params.eval.mode;
if strcmp(mode, "full")
    omega_idx = (1:S).';
    return;
end

B    = params.eval.B;
Kres = params.eval.K_resamp;
seed = params.eval.seed;

if B >= S
    omega_idx = (1:S).';
    return;
end

block_id = floor((iter_k-1)/max(1,Kres));
stream   = RandStream('mt19937ar','Seed', seed + block_id);

% sample without changing global RNG
r = rand(stream, 1, S);
[~, idx] = sort(r, 'ascend');
omega_idx = idx(1:B).';
end
