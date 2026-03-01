function caseA_opf_interpretability(res_mat, scenarios_test_mat, mpc_case_path, map_csv)
%CASEA_OPF_INTERPRETABILITY  OPF-based physical interpretability plots for Case A.
%
% This script generates voltage and line-loading plots for final policies
% (e.g., RA_Full vs RN_Plain) on a representative hard test day.
%
% Prerequisites:
%   1) MATPOWER installed and added to MATLAB path.
%   2) A MATPOWER case file (.m) for the (modified) IEEE 33-bus feeder.
%   3) A zone-to-bus mapping CSV: data/zone_to_bus.csv with two columns:
%      zone,bus (1-based index), with zone in 1..R and bus in 1..Nbus.
%
% Usage:
  % caseA_opf_interpretability(
  %     'results/caseA_main_kSF10_.../caseA_main_results.mat', ...
  %     'cache/scenarios_test.mat', ...
  %     'data/case33bw.m', ...
  %     'data/zone_to_bus.csv');
%
% Outputs (under the same result folder):
%   figs_opf_caseA/Vm_profile_peak.(png/pdf)
%   figs_opf_caseA/line_loading_peak.(png/pdf)
%   figs_opf_caseA/opf_summary.csv
%
% Notes:
%   - OPF is used here for physical validation/interpretability (voltages and
%     branch loadings). Optimization itself may still use the fast oracle.
%   - The selected day is the worst (maximum composite loss) day under RN_Plain
%     on the hold-out test set, for the representative seed.

    if nargin < 2 || isempty(scenarios_test_mat)
        scenarios_test_mat = 'cache/scenarios_test.mat';
    end
    if nargin < 3 || isempty(mpc_case_path)
        error('mpc_case_path is required (MATPOWER case file for 33-bus).');
    end
    if nargin < 4 || isempty(map_csv)
        map_csv = fullfile('data','zone_to_bus.csv');
    end

    % ---------- load RES and scenarios ----------
    A = load(res_mat,'RES'); RES = A.RES;

    B = load(scenarios_test_mat);
    if isfield(B,'scenarios_test')
        scenarios_test = B.scenarios_test;
    elseif isfield(B,'scenarios')
        scenarios_test = B.scenarios;
    else
        error('Cannot find scenarios_test/scenarios in %s', scenarios_test_mat);
    end

    % ---------- load MATPOWER case ----------
    % ensure the case file folder is on path for feval()
    mpc_dir = fileparts(mpc_case_path);
    if ~isempty(mpc_dir)
        addpath(mpc_dir);
    end
    mpc = feval(strip_ext(mpc_case_path));

    % ---------- mapping: zone -> bus (make M) ----------
    M = build_M_from_zone_bus_csv(map_csv, size(mpc.bus,1), scenarios_test(1).R);

    % ---------- pick methods to compare ----------
    mA = 'RA_Full';
    mB = 'RN_Plain';
    assert(isfield(RES,mA) && isfield(RES,mB), 'RES must contain %s and %s.', mA, mB);

    % pick representative u for each method (median test fitness across seeds)
    uA = pick_representative_u(RES.(mA));
    uB = pick_representative_u(RES.(mB));

    % pick hard day index on test set using RN_Plain (representative seed)
    [s_star, info_day] = pick_hard_day_index(RES.(mB), scenarios_test);
    scen = scenarios_test(s_star);

    fprintf('[OPF] Selected hard test day: idx=%d (%s)\n', s_star, info_day);

    % ---------- run OPF across all slots for both methods ----------
    [VmA, loadA, okA] = run_opf_day(uA, scen, mpc, M);
    [VmB, loadB, okB] = run_opf_day(uB, scen, mpc, M);

    if ~all(okA) || ~all(okB)
        fprintf('[OPF] Warning: some slots failed. okA=%d/%d, okB=%d/%d\n', sum(okA), numel(okA), sum(okB), numel(okB));
    end

    % peak slot determined by worst line loading under RN_Plain
    [~, t_star] = max(max(loadB, [], 1));
    fprintf('[OPF] Peak slot (by max line loading, RN_Plain): t=%d\n', t_star);

    out_dir = fullfile(fileparts(res_mat), 'figs_opf_caseA');
    if ~exist(out_dir,'dir'), mkdir(out_dir); end

    % ---------- Figure 1: Voltage profile at peak slot ----------
% ---------- Figure 1: Voltage profile at peak slot (bar style like the sample) ----------
fig = figure('Color','w');
ax = axes(fig); hold(ax,'on');

x = 1:size(VmA,1);

% thin bars (back -> front) to mimic the uploaded style
b_plain = bar(ax, x, VmB(:,t_star), 0.25, ...
    'LineStyle','none', 'FaceColor',[0.8500 0.3250 0.0980]);  % orange

b_full  = bar(ax, x, VmA(:,t_star), 0.25, ...
    'LineStyle','none', 'FaceColor',[0 0.4470 0.7410], ...    % blue
    'FaceAlpha',0.75);                                        % let orange be visible

% thresholds (keep interpretability)
yline(ax, 0.95,'--');
yline(ax, 1.05,'--');

% style to match the sample: clean axes, no grid, legend top-right horizontal
grid(ax,'off');
box(ax,'off');
ax.Layer = 'top';
ax.XLim = [0.5, numel(x)+0.5];

ylim(ax, [0.85 1.05]);   % 例：0.9~1.1 p.u.

% tick density (optional): change to 1:numel(x) if you want all buses labeled
ax.XTick = 1:2:numel(x);

xlabel(ax,'Bus index');
ylabel(ax,'Voltage magnitude (p.u.)');

legend(ax, [b_plain b_full], {mB, mA}, ...
    'Interpreter','none', 'Location','northeast', 'Orientation','horizontal');

% title(ax, sprintf('Voltage profile at peak slot (t=%d)', t_star));

export_fig(fig, fullfile(out_dir,'Vm_profile_peak'));
close(fig);


    % ---------- Figure 2: Line loading ratio at peak slot ----------
    fig = figure('Color','w'); hold on; grid on;
    plot(loadB(:,t_star), 'LineWidth', 1.6);
    plot(loadA(:,t_star), 'LineWidth', 1.6);
    yline(1.0,'--');
    xlabel('Branch index'); ylabel('Loading ratio (|S|/rateA)');
    legend({mB, mA}, 'Interpreter','none','Location','best');
    title(sprintf('Case A OPF validation: line loading at peak slot (t=%d)', t_star));
    export_fig(fig, fullfile(out_dir,'line_loading_peak')); close(fig);

    % ---------- Summary CSV (violations) ----------
    T = scen.T;
    sumtab = make_summary_table(VmA, loadA, okA, VmB, loadB, okB, mA, mB, T);
    writetable(sumtab, fullfile(out_dir,'opf_summary.csv'));

    fprintf('[OPF] Saved figures + summary to: %s\n', out_dir);
end

% =============================== helpers ===============================

function name = strip_ext(p)
    [~,name,~] = fileparts(p);
end

function M = build_M_from_zone_bus_csv(map_csv, Nbus, R)
    if ~exist(map_csv,'file')
        error('Mapping CSV not found: %s', map_csv);
    end
    T = readtable(map_csv);
    if width(T) < 2
        error('Mapping CSV must have at least two columns: zone,bus');
    end
    zone = T{:,1};
    bus  = T{:,2};
    if any(zone < 1) || any(zone > R)
        error('Zone indices must be in 1..R (R=%d).', R);
    end
    if any(bus < 1) || any(bus > Nbus)
        error('Bus indices must be in 1..Nbus (Nbus=%d).', Nbus);
    end
    M = zeros(Nbus, R);
    for r = 1:R
        idx = find(zone == r);
        if isempty(idx)
            error('Zone %d missing in mapping CSV.', r);
        end
        % allow one-to-one mapping; if multiple rows exist, average split
        b = bus(idx);
        w = ones(numel(b),1) / numel(b);
        for k=1:numel(b)
            M(b(k), r) = M(b(k), r) + w(k);
        end
    end
end

function u = pick_representative_u(block)
    % Choose the seed whose test fitness is median, then use its bestU.
    if ~isfield(block,'out_test') || ~isfield(block,'bestU')
        error('Method block must contain out_test and bestU.');
    end
    outs = block.out_test;
    fit  = cellfun(@(o)o.fitness, outs);
    [~, idx] = sort(fit, 'ascend');
    mid = idx(ceil(numel(idx)/2));
    u = block.bestU(mid,:);
end

function [s_star, info] = pick_hard_day_index(block, scenarios_test)
    % Use the same representative seed as in pick_representative_u,
    % then select the scenario with maximum composite loss L.
    outs = block.out_test;
    fit  = cellfun(@(o)o.fitness, outs);
    [~, idx] = sort(fit, 'ascend');
    mid = idx(ceil(numel(idx)/2));
    o = outs{mid};

    if ~isfield(o,'det') || ~isfield(o.det,'L')
        error('oracle_eval must return det.L (per-scenario loss).');
    end
    L = o.det.L;
    [~, s_star] = max(L);

    info = sprintf('median-seed=%d, maxL=%.4g, day_has_T=%d', mid, max(L), scenarios_test(s_star).T);
end

function [Vm, loading, ok] = run_opf_day(u, scen, mpc_base, M)
    % Run OPF/PF for all slots in a single scenario day.
    R = scen.R; T = scen.T;
    u = u(:).';
    u_ch = u(1:R);
    u_cp = u(R+1:2*R);

    % served EV power per zone/time (kW)
    Pmax = scen.Pmax(:)';
    P_allow = u_ch .* Pmax;
    P_serv = min(scen.P_req_rt, repmat(P_allow(:), 1, T)); % [R x T]

    % edge power per zone/time (kW) using same model as sim_one_scenario
    Pedge_idle = 0; Pedge_peak = 0;
    if isfield(scen,'Pedge_idle') && ~isempty(scen.Pedge_idle), Pedge_idle = scen.Pedge_idle; end
    if isfield(scen,'Pedge_peak') && ~isempty(scen.Pedge_peak), Pedge_peak = scen.Pedge_peak; end
    if isscalar(Pedge_idle), Pedge_idle = Pedge_idle * ones(1,R); end
    if isscalar(Pedge_peak), Pedge_peak = Pedge_peak * ones(1,R); end
    Pedge_idle = max(Pedge_idle, 0);
    Pedge_peak = max(Pedge_peak, Pedge_idle);

    Fcap = scen.Fcap(:)';
    F_allow = max(u_cp .* Fcap, 1e-3);
    rho = scen.lambda_req_rt ./ repmat(F_allow(:), 1, T); % [R x T]
    rhoN = min(max(rho,0),1);
    P_edge = repmat(u_cp(:),1,T) .* (repmat(Pedge_idle(:),1,T) + (repmat(Pedge_peak(:)-Pedge_idle(:),1,T) .* rhoN));

    P_zone = P_serv + P_edge; % [R x T]

    Nbus = size(mpc_base.bus,1);
    Nbr  = size(mpc_base.branch,1);

    Vm = nan(Nbus, T);
    loading = nan(Nbr, T);
    ok = false(1,T);

    mpopt = mpoption('verbose',0,'out.all',0);

    % load power factor (assumption for added load)
    pf_load = 0.95;
    tanphi = tan(acos(pf_load));

    for t=1:T
        mpc = mpc_base;

        % additional load mapped to buses (MW)
        P_add_bus_MW = (M * P_zone(:,t)) / 1000;
        Q_add_bus_MW = P_add_bus_MW * tanphi;

        % add to existing demand
        mpc.bus(:,3) = mpc.bus(:,3) + P_add_bus_MW; % PD
        mpc.bus(:,4) = mpc.bus(:,4) + Q_add_bus_MW; % QD

        % try OPF first; if fails, fallback to PF
        try
            res = runopf(mpc, mpopt);
            if ~isfield(res,'success') || ~res.success
                error('runopf not successful');
            end
        catch
            try
                res = runpf(mpc, mpopt);
                if ~isfield(res,'success') || ~res.success
                    error('runpf not successful');
                end
            catch
                continue;
            end
        end

        ok(t) = true;
        Vm(:,t) = res.bus(:,8); % Vm

        rateA = res.branch(:,6);
        PF = res.branch(:,14); QF = res.branch(:,15);
        Sf = sqrt(PF.^2 + QF.^2);
        ratio = nan(size(Sf));
        idx = rateA > 1e-6;
        ratio(idx) = abs(Sf(idx)) ./ rateA(idx);
        loading(:,t) = ratio;
    end
end

function T = make_summary_table(VmA, loadA, okA, VmB, loadB, okB, mA, mB, Th)
    % Summarize voltage/line violations for the selected day.
    VminA = min(VmA, [], 1, 'omitnan');
    VmaxA = max(VmA, [], 1, 'omitnan');
    VminB = min(VmB, [], 1, 'omitnan');
    VmaxB = max(VmB, [], 1, 'omitnan');

    LmaxA = max(loadA, [], 1, 'omitnan');
    LmaxB = max(loadB, [], 1, 'omitnan');

    uvA = sum(VmA(:) < 0.95);
    ovA = sum(VmA(:) > 1.05);
    olA = sum(loadA(:) > 1.0);

    uvB = sum(VmB(:) < 0.95);
    ovB = sum(VmB(:) > 1.05);
    olB = sum(loadB(:) > 1.0);

    rows = {
        mB, sum(okB), Th, min(VminB), max(VmaxB), max(LmaxB), uvB, ovB, olB;
        mA, sum(okA), Th, min(VminA), max(VmaxA), max(LmaxA), uvA, ovA, olA;
    };

    T = cell2table(rows, 'VariableNames', {
        'method','opf_success_slots','T', ...
        'min_Vm','max_Vm','max_line_loading', ...
        'undervoltage_count','overvoltage_count','line_overload_count'});
end

function export_fig(fig, basepath)
    set(fig,'InvertHardcopy','off');
    print(fig, basepath + ".png", "-dpng", "-r300");
    print(fig, basepath + ".pdf", "-dpdf");
end
