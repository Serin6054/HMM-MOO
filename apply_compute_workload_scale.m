function [scenarios2, params2, info] = apply_compute_workload_scale(scenarios, params, kappaW, R, opts)
%APPLY_COMPUTE_WORKLOAD_SCALE  Scale compute WORKLOAD intensity (cleaner A1 alternative).
%
%   [scenarios2, params2, info] = apply_compute_workload_scale(scenarios, params, kappaW, R)
%   [scenarios2, params2, info] = apply_compute_workload_scale(scenarios, params, kappaW, R, opts)
%
% This scales workload-like fields in scenarios (NOT EV demand), e.g.:
%   W, workload, lambda, arrival, task, cpu, etc.
%
% Use when κ_F capacity scaling is hard to align with the oracle field path.
%
% -------------------------------------------------------------------------

    %#ok<NASGU>
    params2 = params;
    scenarios2 = scenarios;

    if nargin < 5 || isempty(opts), opts = struct(); end
    if ~isfield(opts,'candidatePaths') || isempty(opts.candidatePaths)
        opts.candidatePaths = { ...
            'W', 'W_req', 'Wreq', 'workload', 'Workload', ...
            'lambda_req_rt', 'lambda', 'Lambda', 'arrival', 'arrivals', ...
            'task', 'tasks', 'cpu', 'CPU', ...
            'compute.W', 'compute.workload', 'compute.lambda', ...
            'edge.W', 'edge.workload', 'edge.lambda'};
    end
    if ~isfield(opts,'strict') || isempty(opts.strict), opts.strict = false; end
    if ~isfield(opts,'verbose')|| isempty(opts.verbose), opts.verbose = false; end

    info = struct();
    info.kappaW = kappaW;
    info.scaled_param_fields = {};
    info.scaled_scenario_fields = {};
    info.details = struct();

    [scenarios2, scaledPaths, details] = scale_container(scenarios2, kappaW, opts.candidatePaths);
    info.scaled_scenario_fields = scaledPaths;
    info.details = details;

    if opts.strict && isempty(scaledPaths)
        error('apply_compute_workload_scale:NoOp', ...
              'No workload-like fields were found. Add the real workload field path to opts.candidatePaths.');
    end

    if opts.verbose
        fprintf('[apply_compute_workload_scale] kappaW=%.4g scaled scenario fields: %s\n', ...
            kappaW, cellstr_join(scaledPaths));
    end
end

% --- local helpers (duplicated minimal set to keep this file standalone) ---
function [containerOut, scaledPaths, details] = scale_container(containerIn, kappa, candidatePaths)
    scaledPaths = {};
    details = struct();
    containerOut = containerIn;

    if iscell(containerIn)
        for i = 1:numel(containerIn)
            if isstruct(containerIn{i})
                [containerOut{i}, sP, dP] = scale_struct_by_paths(containerIn{i}, kappa, candidatePaths);
                [scaledPaths, details] = merge_reports(scaledPaths, details, sP, dP);
            end
        end
        return;
    end

    if isstruct(containerIn)
        if numel(containerIn) > 1
            for i = 1:numel(containerIn)
                [containerOut(i), sP, dP] = scale_struct_by_paths(containerIn(i), kappa, candidatePaths);
                [scaledPaths, details] = merge_reports(scaledPaths, details, sP, dP);
            end
        else
            [containerOut, scaledPaths, details] = scale_struct_by_paths(containerIn, kappa, candidatePaths);
        end
        return;
    end
end

function [s, scaledPaths, details] = scale_struct_by_paths(s, kappa, candidatePaths)
    scaledPaths = {};
    details = struct();

    for p = 1:numel(candidatePaths)
        path = candidatePaths{p};
        [ok, val] = try_get_by_path(s, path);
        if ~ok || isempty(val) || ~isnumeric(val), continue; end

        before = val;
        after  = kappa .* before;

        s = set_by_path(s, path, after);

        scaledPaths{end+1} = path; %#ok<AGROW>
        key = sanitize_key(path);

        details.(key) = struct( ...
            'path', path, ...
            'min_before', min(before(:)), 'max_before', max(before(:)), ...
            'min_after',  min(after(:)),  'max_after',  max(after(:)) );
    end

    scaledPaths = unique(scaledPaths, 'stable');
end

function [ok, val] = try_get_by_path(s, path)
    ok = false; val = [];
    try
        parts = strsplit(path, '.');
        val = s;
        for i = 1:numel(parts)
            f = parts{i};
            if ~isstruct(val) || ~isfield(val, f), return; end
            val = val.(f);
        end
        ok = true;
    catch
        ok = false; val = [];
    end
end

function s = set_by_path(s, path, value)
    parts = strsplit(path, '.');
    s = set_by_path_recursive(s, parts, value, 1);
end

function s = set_by_path_recursive(s, parts, value, idx)
    f = parts{idx};
    if idx == numel(parts)
        s.(f) = value;
        return;
    end
    if ~isfield(s, f) || ~isstruct(s.(f))
        s.(f) = struct();
    end
    s.(f) = set_by_path_recursive(s.(f), parts, value, idx+1);
end

function key = sanitize_key(path)
    key = regexprep(path, '[^a-zA-Z0-9_]', '_');
    if isempty(key) || ~isletter(key(1))
        key = ['f_' key];
    end
end

function [scaledPaths, details] = merge_reports(scaledPaths, details, scaledPaths_i, details_i)
    scaledPaths = [scaledPaths(:); scaledPaths_i(:)];
    scaledPaths = unique(scaledPaths, 'stable');

    fns = fieldnames(details_i);
    for k = 1:numel(fns)
        fn = fns{k};
        if ~isfield(details, fn)
            details.(fn) = details_i.(fn);
        else
            details.(fn).min_before = min(details.(fn).min_before, details_i.(fn).min_before);
            details.(fn).max_before = max(details.(fn).max_before, details_i.(fn).max_before);
            details.(fn).min_after  = min(details.(fn).min_after,  details_i.(fn).min_after);
            details.(fn).max_after  = max(details.(fn).max_after,  details_i.(fn).max_after);
        end
    end
end

function out = cellstr_join(c)
    if isempty(c), out = '{}'; return; end
    out = ['{' strjoin(c, ', ') '}'];
end
