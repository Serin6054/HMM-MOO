function latest_dir = find_latest_results_dir(res_root, prefix)
% Find newest folder under res_root whose name starts with prefix.

d = dir(fullfile(res_root, char(prefix) + "*"));
if isempty(d)
    error('No results folder found with prefix %s under %s', prefix, res_root);
end
[~, idx] = max([d.datenum]);
latest_dir = fullfile(res_root, d(idx).name);
end
