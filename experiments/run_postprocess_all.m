function out = run_postprocess_all(cfg)
% EXP-POST
% One-click postprocess entry: setup + day-ahead outputs.

if nargin < 1 || isempty(cfg)
    cfg = local_load_cfg_from_latest();
end

out = struct();
out.setup = postprocess_make_setup_outputs(cfg);
out.day_ahead = postprocess_make_day_ahead_outputs(cfg);

fprintf('[run_postprocess_all] output root: %s\n', fullfile(cfg.out_root, cfg.tag));
fprintf('[run_postprocess_all] table1: %s\n', out.setup.table1);
fprintf('[run_postprocess_all] table3: %s\n', out.day_ahead.table3);
end

function cfg = local_load_cfg_from_latest()
res_root = 'results_experiments';
dd = dir(fullfile(res_root, '*'));
dd = dd([dd.isdir]);
dd = dd(~ismember({dd.name},{'.','..'}));
if isempty(dd), error('No results_experiments/* folder found.'); end
[~,ix] = max([dd.datenum]);
cfg = exp_config_template();
cfg.tag = dd(ix).name;
cache_cfg = fullfile(res_root, cfg.tag, 'cache', 'run_config.mat');
if exist(cache_cfg,'file')==2
    s = load(cache_cfg,'cfg');
    cfg = s.cfg;
end
end
