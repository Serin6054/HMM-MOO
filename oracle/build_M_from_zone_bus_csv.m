function M = build_M_from_zone_bus_csv(map_csv, Nbus, R)
%BUILD_M_FROM_ZONE_BUS_CSV  Build zone->bus mapping matrix M.
%
% Expected CSV format (header allowed):
%   zone,bus
% where zone is 1..R and bus is 1..Nbus.
%
% If a zone appears multiple times, its load is split equally across the
% mapped buses.

if nargin < 3
    error('build_M_from_zone_bus_csv(map_csv, Nbus, R) requires 3 inputs.');
end

if ~exist(map_csv,'file')
    error('Mapping CSV not found: %s', map_csv);
end

T = readtable(map_csv);

% Try common column names
vars = lower(string(T.Properties.VariableNames));

% zone column
iz = find(vars=="zone" | vars=="taz" | vars=="tazid" | vars=="z", 1);
if isempty(iz)
    iz = 1;
end

% bus column
ib = find(vars=="bus" | vars=="busid" | vars=="node" | vars=="n", 1);
if isempty(ib)
    if width(T) >= 2
        ib = 2;
    else
        error('Mapping CSV must contain at least two columns (zone,bus).');
    end
end

zones = T{:,iz};
buses = T{:,ib};

zones = zones(:); buses = buses(:);

M = zeros(Nbus, R);

for r = 1:R
    idx = find(zones == r);
    if isempty(idx)
        error('Zone %d missing in mapping CSV %s.', r, map_csv);
    end
    bs = buses(idx);
    bs = bs(~isnan(bs));
    bs = unique(bs(:));
    if any(bs < 1) || any(bs > Nbus)
        error('Mapping contains out-of-range bus indices for zone %d.', r);
    end
    w = 1/numel(bs);
    for k = 1:numel(bs)
        M(bs(k), r) = M(bs(k), r) + w;
    end
end
end
