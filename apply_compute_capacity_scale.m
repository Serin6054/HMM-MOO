function varargout = apply_compute_capacity_scale(varargin)
%APPLY_COMPUTE_CAPACITY_SCALE  Robust κappa_F (kF) scaling for compute capacity.
%
% This function supports TWO calling conventions (to match your codebase + the
% earlier patch):
%
% (A) "oracle style" (your snippet):
%   [scenarios2, params2, info] = apply_compute_capacity_scale(scenarios, params, kappaF, R)
%   [scenarios2, params2, info] = apply_compute_capacity_scale(scenarios, params, kappaF, R, opts)
%
% (B) "simple style" (earlier patch):
%   [scen2, info] = apply_compute_capacity_scale(scen, kappaF)
%   [scen2, info] = apply_compute_capacity_scale(scen, kappaF, opts)
%
% What it does:
%   - Multiplies the *scenario* compute-capacity field(s) used by the oracle,
%     primarily 'Fcap' (and several common aliases / nested paths).
%   - Prints/returns an "info" struct with:
%       info.kappaF
%       info.scaled_param_fields
%       info.scaled_scenario_fields
%       info.details
%
% IMPORTANT:
%   If info.scaled_scenario_fields is {}, then κappa_F is a NO-OP and your A1
%   sweep will be flat. In that case, add your real field path to opts.candidatePaths.
%
% -------------------------------------------------------------------------

    % ---------- dispatch by signature ----------
    if nargin < 2
        error('apply_compute_capacity_scale:NotEnoughInputs', ...
              'Not enough inputs. See help apply_compute_capacity_scale.');
    end

    % Oracle-style: (scenarios, params, kappaF, R, [opts])
    if nargin >= 4 && isstruct(varargin{2}) && isscalar(varargin{3})
        scenarios = varargin{1};
        params    = varargin{2};
        kappaF    = varargin{3};
        % R is accepted for compatibility but not required for scaling itself:
        %#ok<NASGU>
        R         = varargin{4};
        if nargin >= 5, opts = varargin{5}; else, opts = struct(); end

        [scenarios2, info] = scale_scenarios_only(scenarios, kappaF, opts);
        params2 = params; % default: unchanged

        % optional: allow scaling param fields too (rare; keep empty unless configured)
        if isfield(opts,'paramPaths') && ~isempty(opts.paramPaths)
            [params2, scaledParamPaths, detailsP] = scale_struct_by_paths(params2, kappaF, opts.paramPaths);
            info.scaled_param_fields = scaledParamPaths;
            info.details = merge_detail_structs(info.details, detailsP);
        else
            info.scaled_param_fields = {};
        end

        varargout = {scenarios2, params2, info};
        return;
    end

    % Simple-style: (scen, kappaF, [opts])
    scen  = varargin{1};
    kappaF = varargin{2};
    if nargin >= 3, opts = varargin{3}; else, opts = struct(); end

    [scen2, info] = scale_scenarios_only(scen, kappaF, opts);
    info.scaled_param_fields = {};

    varargout = {scen2, info};
end

% ============================= core scaling =============================

function [scen2, info] = scale_scenarios_only(scen, kappaF, opts)
    if nargin < 3 || isempty(opts), opts = struct(); end
    if ~isfield(opts,'candidatePaths') || isempty(opts.candidatePaths)
        % Put your real field FIRST. Add yours here if oracle uses a different path.
        opts.candidatePaths = { ...
            'Fcap', ...                 % <--- main target
            'F_cap', 'Fcap_z', 'Fmax', 'Fmax_z', ...
            'compute.Fcap', 'compute.F_cap', ...
            'edge.Fcap', 'edge.F_cap', ...
            'cap.Fcap', 'cap.F_cap', ...
            'F_z', 'F_nom', 'F_nominal'};
    end
    if ~isfield(opts,'strict') || isempty(opts.strict), opts.strict = false; end
    if ~isfield(opts,'verbose')|| isempty(opts.verbose), opts.verbose = false; end

    info = struct();
    info.kappaF = kappaF;
    info.scaled_scenario_fields = {};
    info.scaled_param_fields = {}; % will be set by caller if needed
    info.details = struct();

    scen2 = scen;

    % Support struct array / cell / single struct
    [scen2, scaledPaths, details] = scale_container(scen2, kappaF, opts.candidatePaths);

    info.scaled_scenario_fields = scaledPaths;
    info.details = details;

    if opts.strict && isempty(scaledPaths)
        error(['apply_compute_capacity_scale:NoOp: none of the candidate capacity fields were found. ' ...
               'Add the correct field path to opts.candidatePaths (the one used inside oracle_eval/sim_one_scenario).']);
    end

    if opts.verbose
        fprintf('[apply_compute_capacity_scale] kappaF=%.4g scaled scenario fields: %s\n', ...
            kappaF, cellstr_join(scaledPaths));
    end
end

% ============================= helpers =============================

function [containerOut, scaledPaths, details] = scale_container(containerIn, kappaF, candidatePaths)
    scaledPaths = {};
    details = struct();
    containerOut = containerIn;

    if iscell(containerIn)
        for i = 1:numel(containerIn)
            if isstruct(containerIn{i})
                [containerOut{i}, sP, dP] = scale_struct_by_paths(containerIn{i}, kappaF, candidatePaths);
                [scaledPaths, details] = merge_reports(scaledPaths, details, sP, dP);
            end
        end
        return;
    end

    if isstruct(containerIn)
        if numel(containerIn) > 1
            for i = 1:numel(containerIn)
                [containerOut(i), sP, dP] = scale_struct_by_paths(containerIn(i), kappaF, candidatePaths);
                [scaledPaths, details] = merge_reports(scaledPaths, details, sP, dP);
            end
        else
            [containerOut, scaledPaths, details] = scale_struct_by_paths(containerIn, kappaF, candidatePaths);
        end
        return;
    end
end

function [s, scaledPaths, details] = scale_struct_by_paths(s, kappaF, candidatePaths)
    scaledPaths = {};
    details = struct();

    for p = 1:numel(candidatePaths)
        path = candidatePaths{p};
        [ok, val] = try_get_by_path(s, path);
        if ~ok || isempty(val) || ~isnumeric(val), continue; end

        before = val;
        after  = kappaF .* before;

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

function s = merge_detail_structs(a, b)
    s = a;
    fns = fieldnames(b);
    for i = 1:numel(fns)
        fn = fns{i};
        if ~isfield(s, fn)
            s.(fn) = b.(fn);
        else
            s.(fn).min_before = min(s.(fn).min_before, b.(fn).min_before);
            s.(fn).max_before = max(s.(fn).max_before, b.(fn).max_before);
            s.(fn).min_after  = min(s.(fn).min_after,  b.(fn).min_after);
            s.(fn).max_after  = max(s.(fn).max_after,  b.(fn).max_after);
        end
    end
end

function out = cellstr_join(c)
    if isempty(c), out = '{}'; return; end
    out = ['{' strjoin(c, ', ') '}'];
end
