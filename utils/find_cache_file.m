function fpath = find_cache_file(cache_dir, keywords)
%FIND_CACHE_FILE Find a .mat file in cache_dir whose name contains all keywords.
%   fpath = find_cache_file(cache_dir, {'design','scenarios'})
%
% If multiple matches are found, returns the most recently modified file.

if nargin < 2 || isempty(keywords)
    keywords = {};
end

if ~isfolder(cache_dir)
    error('Cache directory not found: %s', cache_dir);
end

files = dir(fullfile(cache_dir, '*.mat'));
if isempty(files)
    error('No .mat files found in cache directory: %s', cache_dir);
end

kw = lower(string(keywords));
match = false(numel(files), 1);
for i = 1:numel(files)
    name_i = lower(string(files(i).name));
    ok = true;
    for k = 1:numel(kw)
        if ~contains(name_i, kw(k))
            ok = false;
            break;
        end
    end
    match(i) = ok;
end

idx = find(match);
if isempty(idx)
    % fallback: if no all-keyword match, try any-keyword match
    anyMatch = false(numel(files), 1);
    for i = 1:numel(files)
        name_i = lower(string(files(i).name));
        ok = false;
        for k = 1:numel(kw)
            if contains(name_i, kw(k))
                ok = true;
                break;
            end
        end
        anyMatch(i) = ok;
    end
    idx = find(anyMatch);
end

if isempty(idx)
    error('No cache file match for keywords: %s', strjoin(cellstr(keywords), ', '));
end

% choose most recently modified
[~, order] = sort([files(idx).datenum], 'descend');
chosen = idx(order(1));
fpath = fullfile(cache_dir, files(chosen).name);
end
