function out = run_all()
%RUN_ALL One-click experiment launcher.

cfg = exp_config_template();
out = run_experiments(cfg);
end
