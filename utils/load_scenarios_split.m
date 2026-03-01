function out = load_scenarios_split(varargin)
%LOAD_SCENARIOS_SPLIT Robust loader for design/test scenario sets produced by step1b.
%
% Usage:
%   out = load_scenarios_split();
%   out = load_scenarios_split('cache_dir','cache');
%
% Returns struct out with fields (if available):
%   scenarios_design, scenarios_test, meta, params, u0
%
% The loader searches common cache filenames:
%   * scenarios_design*.mat / scenarios_test*.mat
%   * design*.mat / test*.mat
%   * train*.mat / test*.mat

p = inputParser;
addParameter(p, 'cache_dir', 'cache', @(s)ischar(s) || isstring(s));
parse(p, varargin{:});
cache_dir = char(p.Results.cache_dir);

out = struct();

% find design and test files
try
    f_design = find_cache_file(cache_dir, {'design'});
catch
    try
        f_design = find_cache_file(cache_dir, {'train'});
    catch
        f_design = '';
    end
end

try
    f_test   = find_cache_file(cache_dir, {'test'});
catch
    f_test = '';
end

% load design
if ~isempty(f_design)
    S = load(f_design);
    out = merge_loaded_struct(out, S);
    if isfield(S, 'scenarios_design')
        out.scenarios_design = S.scenarios_design;
    elseif isfield(S, 'scenarios')
        out.scenarios_design = S.scenarios;
    elseif isfield(S, 'scenarios_train')
        out.scenarios_design = S.scenarios_train;
    end
end

% load test
if ~isempty(f_test)
    S = load(f_test);
    out = merge_loaded_struct(out, S);
    if isfield(S, 'scenarios_test')
        out.scenarios_test = S.scenarios_test;
    elseif isfield(S, 'scenarios')
        % only set if not already
        if ~isfield(out, 'scenarios_test')
            out.scenarios_test = S.scenarios;
        end
    end
end

% If still missing, try a single split file
if ~isfield(out,'scenarios_design') || ~isfield(out,'scenarios_test')
    try
        f_split = find_cache_file(cache_dir, {'split'});
        S = load(f_split);
        out = merge_loaded_struct(out, S);
        if isfield(S,'scenarios_design'); out.scenarios_design = S.scenarios_design; end
        if isfield(S,'scenarios_test');   out.scenarios_test   = S.scenarios_test; end
        if isfield(S,'scenarios_train');  out.scenarios_design = S.scenarios_train; end
    catch
        % ignore
    end
end

% sanity checks
if isfield(out, 'scenarios_design')
    out.S_design = numel(out.scenarios_design);
end
if isfield(out, 'scenarios_test')
    out.S_test = numel(out.scenarios_test);
end

if ~isfield(out, 'meta')
    out.meta = infer_meta_from_scenarios(out);
end

end

function out = merge_loaded_struct(out, S)
% Merge common structs if present
fields = fieldnames(S);
for i = 1:numel(fields)
    f = fields{i};
    if any(strcmp(f, {'meta','params','u0','params0'}))
        if strcmp(f,'params0')
            out.params = S.(f);
        else
            out.(f) = S.(f);
        end
    end
end
end

function meta = infer_meta_from_scenarios(out)
meta = struct();
sc = [];
if isfield(out,'scenarios_design') && ~isempty(out.scenarios_design)
    sc = out.scenarios_design(1);
elseif isfield(out,'scenarios_test') && ~isempty(out.scenarios_test)
    sc = out.scenarios_test(1);
end
if ~isempty(sc)
    if isfield(sc,'T'); meta.T = sc.T; end
    if isfield(sc,'dt'); meta.dt = sc.dt; end
    if isfield(sc,'P_EV_req')
        [meta.R, meta.T] = size(sc.P_EV_req);
    elseif isfield(sc,'P_req_rt')
        [meta.R, meta.T] = size(sc.P_req_rt);
    end
end
end
