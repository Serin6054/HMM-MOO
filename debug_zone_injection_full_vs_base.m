function debug_zone_injection_full_vs_base(matfile, which_set)
if nargin<1, matfile='caseA_methods_results.mat'; end
if nargin<2, which_set='test'; end
which_set = lower(string(which_set));

% scenarios
[scen_design, scen_test] = load_scenarios_split(pwd);
scen_set = scen_test;
if which_set=="design", scen_set=scen_design; end
S = numel(scen_set);
R = scen_set(1).R;
T = scen_set(1).T;

% mapping
tbl = readtable(fullfile('data','zone_to_bus.csv'));
zone_id = tbl{:,1}; bus_id = tbl{:,2};
if iscell(zone_id)||isstring(zone_id), zone_id=str2double(string(zone_id)); end
if iscell(bus_id)||isstring(bus_id),  bus_id=str2double(string(bus_id)); end
zoneBus = nan(R,1);
for z=1:R
    j=find(zone_id==z,1,'first');
    zoneBus(z)=bus_id(j);
end

% load FULL bestU
Sres = load(matfile,'results'); results=Sres.results;
[u_full,~] = pick_best_u(results.FULL, which_set);
u_base = [ones(1,R), ones(1,R)];
% --------- quota binding check (critical) ----------
u_ch_full = u_full(1:R).';
Pmax = double(scen_set(1).Pmax(:));            % R x 1
P_allow_full = u_ch_full .* Pmax;              % R x 1

bind_cnt   = zeros(R,1);   % number of (scenario,time) slots where req > allow
max_excess = zeros(R,1);   % max(req-allow) over all (scenario,time)

total_slots = S*T;


% aggregate per-zone stats (over scenarios & time)
P_req_mean = zeros(R,1);
P_req_max  = zeros(R,1);
P_serv_base_mean = zeros(R,1);
P_serv_full_mean = zeros(R,1);

for s=1:S
    scen = scen_set(s);

    % ----- request power from scenario -----
    % 尝试自动找字段名（你工程里常见是 P_req_rt 或 P_req）
    if isfield(scen,'P_req_rt')
        P_req = scen.P_req_rt;
    elseif isfield(scen,'P_req')
        P_req = scen.P_req;
    else
        error('Scenario has no P_req_rt/P_req field.');
    end

    P_req = coerce_RxT(double(P_req),R,T);
    P_req(~isfinite(P_req))=0;
    A = repmat(P_allow_full, 1, T);          % R x T
bind_cnt = bind_cnt + sum(P_req > (A + 1e-9), 2);

excess = max(P_req - A, 0);
max_excess = max(max_excess, max(excess, [], 2));


    P_req_mean = P_req_mean + mean(P_req,2);
    P_req_max  = max(P_req_max, max(P_req,[],2));

    % ----- served power from sim -----
    mb = sim_one_scenario(u_base, scen);
    mf = sim_one_scenario(u_full, scen);

    Pb = coerce_RxT(double(mb.debug.P_EV_serv),R,T); Pb(~isfinite(Pb))=0;
    Pf = coerce_RxT(double(mf.debug.P_EV_serv),R,T); Pf(~isfinite(Pf))=0;

    P_serv_base_mean = P_serv_base_mean + mean(Pb,2);
    P_serv_full_mean = P_serv_full_mean + mean(Pf,2);
end

P_req_mean = P_req_mean / S;
P_serv_base_mean = P_serv_base_mean / S;
P_serv_full_mean = P_serv_full_mean / S;

TBL = table((1:R)', zoneBus, P_req_mean, P_req_max, P_serv_base_mean, P_serv_full_mean, ...
    'VariableNames',{'zone','bus','req_mean','req_max','serv_base_mean','serv_full_mean'});
disp(TBL);
bind_rate = bind_cnt / total_slots;

TBL2 = table((1:R)', zoneBus, Pmax, u_ch_full, P_allow_full, P_req_max, bind_rate, max_excess, ...
    'VariableNames',{'zone','bus','Pmax','u_ch_full','P_allow_full','req_max','bind_rate','max_excess'});
disp(TBL2);

fprintf('\nZones with bind_rate==0 (quota never binds): %s\n', mat2str(find(bind_rate==0)'));

fprintf('\nZones with req_max==0 (no demand): %s\n', mat2str(find(P_req_max==0)'));
fprintf('Zones with serv_full_mean==0: %s\n', mat2str(find(abs(P_serv_full_mean)<1e-12)'));
end

function A = coerce_RxT(A,R,T)
sz=size(A);
if isequal(sz,[R,T]), return; end
if isequal(sz,[T,R]), A=A.'; return; end
error('Unexpected size %s, expect %dx%d or %dx%d', mat2str(sz), R,T,T,R);
end

function [u_best, seed_best] = pick_best_u(block, which_set)
outs_field = "out_" + which_set;
outs = block.(outs_field);
n = numel(outs);
fit = inf(n,1);
for k=1:n
    o = outs{k};
    if isfield(o,'fitness'), fit(k)=o.fitness; end
end
[~,kbest]=min(fit);

BU = block.bestU;
if size(BU,1)==n
    u_best = BU(kbest,:);
elseif size(BU,2)==n
    u_best = BU(:,kbest).';
else
    u_best = BU(:).';
end
seed_best = block.seeds(kbest);
end
