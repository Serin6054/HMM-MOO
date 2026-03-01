function cfg = exp_config_template()
%EXP_CONFIG_TEMPLATE Default configuration for experiment runner.

cfg = struct();
cfg.out_root = 'results_experiments';
cfg.tag = datestr(now, 'yyyymmdd_HHMMSS');
cfg.alpha_cvar = 0.95;

cfg.scen_design_path = fullfile('cache','scenarios_design.mat');
cfg.scen_test_path   = fullfile('cache','scenarios_test.mat');
cfg.split_path       = fullfile('cache','split.mat');

cfg.use_opf = false;
cfg.case_list = {'C1','C2','C3','C4','C5'};

cfg.params_base = oracle_make_params();
cfg.params_base.alpha = cfg.alpha_cvar;
cfg.params_base.u_mode = 'quota';  % EXP-U-SCALE
end
