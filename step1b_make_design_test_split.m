function split = step1b_make_design_test_split(opts)
%STEP1B_MAKE_DESIGN_TEST_SPLIT  Create Design/Test scenario split (hold-out).
%
% Usage:
%   step1b_make_design_test_split
%   split = step1b_make_design_test_split(opts)
%
% Default method: 'calendar' (time-based split), with robust fallbacks.
%
% Outputs:
%   cache/split.mat
%   cache/scenarios_design.mat
%   cache/scenarios_test.mat
%
% Notes:
%   This script assumes you already have cache/scenarios.mat containing variable 'scenarios'.
%   If scenarios have no usable date/time fields, it falls back to chronological 80/20 split.
%
% -------------------------------------------------------------------------

    if nargin < 1 || isempty(opts), opts = struct(); end

    % ---- default options ----
    if ~isfield(opts,'method') || isempty(opts.method)
        opts.method = 'calendar';   % 'calendar' | 'chronological' | 'random'
    end
    if ~isfield(opts,'design_start') || isempty(opts.design_start)
        opts.design_start = datetime(2022,9,1);
    end
    if ~isfield(opts,'design_end') || isempty(opts.design_end)
        opts.design_end   = datetime(2022,12,31);
    end
    if ~isfield(opts,'test_start') || isempty(opts.test_start)
        opts.test_start   = datetime(2023,1,1);
    end
    if ~isfield(opts,'test_end') || isempty(opts.test_end)
        opts.test_end     = datetime(2023,2,28);
    end
    if ~isfield(opts,'chron_ratio') || isempty(opts.chron_ratio)
        opts.chron_ratio  = 0.8;
    end
    if ~isfield(opts,'seed') || isempty(opts.seed)
        opts.seed = 2025;
    end

    % ---- load scenarios ----
    if exist('./cache/scenarios.mat','file') ~= 2
        error('Cannot find ./cache/scenarios.mat. Run step1_prepare_scenarios first.');
    end
    S = load('./cache/scenarios.mat','scenarios');
    if ~isfield(S,'scenarios')
        error('./cache/scenarios.mat does not contain variable ''scenarios''.');
    end
    scenarios = S.scenarios;
    N = numel(scenarios);
    if N < 5
        error('Too few scenarios (%d).', N);
    end

    % ---- extract per-scenario date (best effort) ----
    [days, okMask] = extract_scenario_days(scenarios);

    % ---- perform split ----
    method = lower(string(opts.method));
    designMask = false(1,N);
    testMask   = false(1,N);

    if method == "calendar"
        if any(okMask)
            designMask = okMask & (days >= opts.design_start) & (days <= opts.design_end);
            testMask   = okMask & (days >= opts.test_start)   & (days <= opts.test_end);

            % If either side is empty or too small, fall back
            if nnz(designMask) < 3 || nnz(testMask) < 3
                warning('Calendar split produced too few scenarios (design=%d, test=%d). Falling back to chronological 80/20.', ...
                    nnz(designMask), nnz(testMask));
                [designMask, testMask] = chronological_split(days, okMask, opts.chron_ratio);
                method = "chronological_fallback";
            end
        else
            warning('No usable scenario date fields found. Falling back to chronological 80/20 by index.');
            [designMask, testMask] = index_split(N, opts.chron_ratio);
            method = "chronological_fallback";
        end

    elseif method == "chronological"
        if any(okMask)
            [designMask, testMask] = chronological_split(days, okMask, opts.chron_ratio);
        else
            [designMask, testMask] = index_split(N, opts.chron_ratio);
        end

    elseif method == "random"
        rng(opts.seed);
        idx = randperm(N);
        k = max(1, floor(opts.chron_ratio * N));
        designMask(idx(1:k)) = true;
        testMask(idx(k+1:end)) = true;

    else
        error('Unknown split.method: %s (supported: calendar|chronological|random)', string(opts.method));
    end

    % Ensure disjoint and cover
    testMask(designMask) = false;
    if nnz(designMask) + nnz(testMask) < N
        % Put remaining into design by default
        leftover = ~(designMask | testMask);
        designMask(leftover) = true;
    end

    design_idx = find(designMask);
    test_idx   = find(testMask);

    scenarios_design = scenarios(design_idx);
    scenarios_test   = scenarios(test_idx);

    % ---- save ----
    if exist('./cache','dir') ~= 7
        mkdir('./cache');
    end

    split = struct();
    split.method = char(method);
    split.N = N;
    split.design_idx = design_idx;
    split.test_idx = test_idx;
    split.opts = opts;

    save('./cache/split.mat','split');
    save('./cache/scenarios_design.mat','scenarios_design');
    save('./cache/scenarios_test.mat','scenarios_test');

    fprintf('[Split] method=%s | N=%d | design=%d | test=%d\n', split.method, N, numel(design_idx), numel(test_idx));
end

% ======================= helpers =======================

function [days, okMask] = extract_scenario_days(scenarios)
    N = numel(scenarios);
    days = NaT(1,N);
    okMask = false(1,N);

    for i = 1:N
        s = scenarios(i);

        % 1) direct datetime field
        if isfield(s,'date') && ~isempty(s.date)
            d = to_datetime(s.date);
            if ~isnat(d), days(i) = dateshift(d,'start','day'); okMask(i)=true; continue; end
        end

        % 2) common string fields
        cand = {};
        if isfield(s,'day') && ~isempty(s.day), cand{end+1} = s.day; end %#ok<AGROW>
        if isfield(s,'date_str') && ~isempty(s.date_str), cand{end+1} = s.date_str; end %#ok<AGROW>
        if isfield(s,'datestr') && ~isempty(s.datestr), cand{end+1} = s.datestr; end %#ok<AGROW>
        if isfield(s,'id') && ischar(s.id), cand{end+1} = s.id; end %#ok<AGROW>

        for k = 1:numel(cand)
            d = try_parse_date_string(cand{k});
            if ~isnat(d), days(i) = dateshift(d,'start','day'); okMask(i)=true; break; end
        end
        if okMask(i), continue; end

        % 3) time vector start
        if isfield(s,'time') && ~isempty(s.time)
            d = to_datetime(s.time(1));
            if ~isnat(d), days(i) = dateshift(d,'start','day'); okMask(i)=true; continue; end
        end
        if isfield(s,'t0') && ~isempty(s.t0)
            d = to_datetime(s.t0);
            if ~isnat(d), days(i) = dateshift(d,'start','day'); okMask(i)=true; continue; end
        end
    end
end

function d = to_datetime(x)
    d = NaT;
    try
        if isa(x,'datetime')
            d = x;
        elseif isnumeric(x)
            % Could be datenum or POSIX
            if x > 1e9  % likely POSIX seconds
                d = datetime(x, 'ConvertFrom','posixtime');
            else        % datenum
                d = datetime(x, 'ConvertFrom','datenum');
            end
        elseif isstring(x) || ischar(x)
            d = try_parse_date_string(x);
        end
    catch
        d = NaT;
    end
end

function d = try_parse_date_string(s)
    d = NaT;
    try
        s = char(string(s));
        % common formats: YYYY-MM-DD, YYYY/MM/DD, YYYYMMDD
        if ~isempty(regexp(s,'\d{4}[-/]\d{2}[-/]\d{2}','once'))
            d = datetime(s, 'InputFormat','yyyy-MM-dd');
        elseif ~isempty(regexp(s,'\d{8}','once'))
            d = datetime(s(1:8), 'InputFormat','yyyyMMdd');
        else
            % last resort: let datetime guess
            d = datetime(s);
        end
    catch
        d = NaT;
    end
end

function [designMask, testMask] = chronological_split(days, okMask, ratio)
    N = numel(days);
    designMask = false(1,N);
    testMask   = false(1,N);

    idxOk = find(okMask);
    [~, ord] = sort(days(idxOk));
    idxSorted = idxOk(ord);

    k = max(1, floor(ratio * numel(idxSorted)));
    designMask(idxSorted(1:k)) = true;
    testMask(idxSorted(k+1:end)) = true;

    % any missing-date scenarios -> put into design by default
    missing = ~okMask;
    designMask(missing) = true;
end

function [designMask, testMask] = index_split(N, ratio)
    designMask = false(1,N);
    testMask   = false(1,N);
    k = max(1, floor(ratio * N));
    designMask(1:k) = true;
    testMask(k+1:end) = true;
end
