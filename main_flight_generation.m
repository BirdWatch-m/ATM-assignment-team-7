rng('shuffle');

% number of flights to generate
numFlights = 5;

% constraints for flight generation
minDistanceKm = 1000;
maxDistanceKm = 4000;

% load data
[airportsTable, runwaysTable] = loadAirportDataLocal("airports.csv", "runways.csv");
aircraftTable = getAircraftDatabaseLocal("Aircraft_BADA_Mapping.csv");
airportCatalog = buildAirportRunwayCatalogLocal(airportsTable, runwaysTable);

% generate flights
flights = generateRandomFlightsLocal(airportCatalog, aircraftTable, numFlights, minDistanceKm, maxDistanceKm);

disp("Generated flights:")
disp(flights)

% Jose's part - time of arrival + conflicts
% for i=1:numFligths
    % computeTime(..)
% end

% plot flights on globe
plotFlightsOnGlobeLocal(flights);

%% - MAIN CODE FUNCTIONS -

% Airport data loading function 
function [airportsTable, runwaysTable] = loadAirportDataLocal(airportsFile, runwaysFile)
airportsTable = readtable(airportsFile, 'TextType', 'string');
runwaysTable = readtable(runwaysFile, 'TextType', 'string');

numericRunwayColumns = ["length_ft", "width_ft", "lighted", "closed"];

for i = 1:numel(numericRunwayColumns)
    columnName = numericRunwayColumns(i);
    if iscell(runwaysTable.(columnName)) || isstring(runwaysTable.(columnName))
        runwaysTable.(columnName) = str2double(string(runwaysTable.(columnName)));
    end
end
end

%% Aircraft Database 
% QUESTION: what aircraft should be included? The ones in BADA maybe?
function aircraftTable = getAircraftDatabaseLocal(filename)
if nargin < 1
    filename = "Aircraft_BADA_Mapping.csv";
end

rawTable = readtable(filename, 'Delimiter', ';', 'TextType', 'string', 'VariableNamingRule', 'preserve');

aircraft_type = rawTable.("Aircraft Type");
aircraft_category = rawTable.("Category");

min_runway_length_ft = rawTable.("Min Runway Length (ft)");
if iscell(min_runway_length_ft) || isstring(min_runway_length_ft)
    min_runway_length_ft = str2double(string(min_runway_length_ft));
end

min_runway_width_m = rawTable.("Min Runway Width (m)");
if iscell(min_runway_width_m) || isstring(min_runway_width_m)
    min_runway_width_m = str2double(string(min_runway_width_m));
end

if ismember("Min Runway Width (ft)", rawTable.Properties.VariableNames)
    min_runway_width_ft = rawTable.("Min Runway Width (ft)");
    if iscell(min_runway_width_ft) || isstring(min_runway_width_ft)
        min_runway_width_ft = str2double(string(min_runway_width_ft));
    end
    missingWidthMask = isnan(min_runway_width_ft);
    min_runway_width_ft(missingWidthMask) = min_runway_width_m(missingWidthMask) * 3.28084;
else
    min_runway_width_ft = min_runway_width_m * 3.28084;
end

aircraftTable = table( ...
    aircraft_type, aircraft_category, min_runway_length_ft, min_runway_width_ft, ...
    'VariableNames', { ...
    'aircraft_type', 'aircraft_category', 'min_runway_length_ft', ...
    'min_runway_width_ft'});
end

%% Airport Runway Catalog 

function airportCatalog = buildAirportRunwayCatalogLocal(airportsTable, runwaysTable)
isEuropean = airportsTable.continent == "EU";
isRelevantType = airportsTable.type == "large_airport" | airportsTable.type == "medium_airport";
hasIcao = strlength(strtrim(airportsTable.icao_code)) > 0;
hasCoordinates = ~isnan(airportsTable.latitude_deg) & ~isnan(airportsTable.longitude_deg);

filteredAirports = airportsTable(isEuropean & isRelevantType & hasIcao & hasCoordinates, :);

runwaysTable.airport_ident = string(runwaysTable.airport_ident);
runwaysTable.le_ident = string(runwaysTable.le_ident);
runwaysTable.he_ident = string(runwaysTable.he_ident);
runwaysTable.surface = upper(strtrim(string(runwaysTable.surface)));

hasRunwayId = strlength(strtrim(runwaysTable.le_ident)) > 0 | strlength(strtrim(runwaysTable.he_ident)) > 0;
isOpen = isnan(runwaysTable.closed) | runwaysTable.closed == 0;
hasLength = ~isnan(runwaysTable.length_ft) & runwaysTable.length_ft > 0;
hasWidth = ~isnan(runwaysTable.width_ft) & runwaysTable.width_ft > 0;

usableRunways = runwaysTable(hasRunwayId & isOpen & hasLength & hasWidth, :);

airportCatalog = struct( ...
    'icao', {}, ...
    'name', {}, ...
    'airport_type', {}, ...
    'country', {}, ...
    'latitude_deg', {}, ...
    'longitude_deg', {}, ...
    'runways', {});

for i = 1:height(filteredAirports)
    airportIcao = filteredAirports.icao_code(i);
    airportRunways = usableRunways(usableRunways.airport_ident == airportIcao, :);

    if isempty(airportRunways)
        continue
    end

    airportEntry.icao = airportIcao;
    airportEntry.name = filteredAirports.name(i);
    airportEntry.airport_type = filteredAirports.type(i);
    airportEntry.country = filteredAirports.country_name(i);
    airportEntry.latitude_deg = filteredAirports.latitude_deg(i);
    airportEntry.longitude_deg = filteredAirports.longitude_deg(i);
    airportEntry.runways = airportRunways;

    airportCatalog(end + 1) = airportEntry; %#ok<AGROW>
end
end



%% Check if runway supports aircraft
% QUESTION: what are the conditions for each aircraft type?

function supportedMask = runwaySupportsAircraftLocal(runwayTable, aircraftRow)
if isempty(runwayTable)
    supportedMask = false(0, 1);
    return
end

lengthOk = runwayTable.length_ft >= aircraftRow.min_runway_length_ft;
widthOk = runwayTable.width_ft >= aircraftRow.min_runway_width_ft;
isOpen = isnan(runwayTable.closed) | runwayTable.closed == 0;

supportedMask = lengthOk & widthOk & isOpen;
end


%% Great-circle distance

function distanceKm = greatCircleKmLocal(lat1Deg, lon1Deg, lat2Deg, lon2Deg)
earthRadiusKm = 6371.0;

lat1Rad = deg2rad(lat1Deg);
lon1Rad = deg2rad(lon1Deg);
lat2Rad = deg2rad(lat2Deg);
lon2Rad = deg2rad(lon2Deg);

deltaLat = lat2Rad - lat1Rad;
deltaLon = lon2Rad - lon1Rad;

a = sin(deltaLat / 2).^2 + cos(lat1Rad) .* cos(lat2Rad) .* sin(deltaLon / 2).^2;
c = 2 * atan2(sqrt(a), sqrt(1 - a));

distanceKm = earthRadiusKm * c;
end


% Generate random flights function
function flights = generateRandomFlightsLocal(airportCatalog, aircraftTable, numFlights, minDistanceKm, maxDistanceKm)
maxAttemptsPerFlight = 250;

flightId = strings(numFlights, 1);
aircraftType = strings(numFlights, 1);
aircraftCategory = strings(numFlights, 1);
adep = strings(numFlights, 1);
adepName = strings(numFlights, 1);
depRunway = strings(numFlights, 1);
ades = strings(numFlights, 1);
adesName = strings(numFlights, 1);
arrRunway = strings(numFlights, 1);
distanceKm = nan(numFlights, 1);
depLatitudeDeg = nan(numFlights, 1);
depLongitudeDeg = nan(numFlights, 1);
arrLatitudeDeg = nan(numFlights, 1);
arrLongitudeDeg = nan(numFlights, 1);

for flightIndex = 1:numFlights
    flightWasGenerated = false;

    for attempt = 1:maxAttemptsPerFlight
        aircraftRow = aircraftTable(randi(height(aircraftTable)), :);
        departureCandidates = findSupportingAirportsLocal(airportCatalog, aircraftRow);

        if isempty(departureCandidates)
            continue
        end

        departureAirportIndex = departureCandidates(randi(numel(departureCandidates)));
        departureAirport = airportCatalog(departureAirportIndex);
        departureRunwayMask = runwaySupportsAircraftLocal(departureAirport.runways, aircraftRow);
        departureRunways = departureAirport.runways(departureRunwayMask, :);

        if isempty(departureRunways)
            continue
        end

        [arrivalCandidates, candidateDistances] = findArrivalCandidatesLocal( ...
            airportCatalog, departureAirportIndex, aircraftRow, minDistanceKm, maxDistanceKm);

        if isempty(arrivalCandidates)
            continue
        end

        arrivalChoice = randi(numel(arrivalCandidates));
        arrivalAirportIndex = arrivalCandidates(arrivalChoice);
        arrivalAirport = airportCatalog(arrivalAirportIndex);
        arrivalRunwayMask = runwaySupportsAircraftLocal(arrivalAirport.runways, aircraftRow);
        arrivalRunways = arrivalAirport.runways(arrivalRunwayMask, :);

        chosenDepartureRunway = departureRunways(randi(height(departureRunways)), :);
        chosenArrivalRunway = arrivalRunways(randi(height(arrivalRunways)), :);

        flightId(flightIndex) = compose("F%03d", flightIndex);
        aircraftType(flightIndex) = aircraftRow.aircraft_type;
        aircraftCategory(flightIndex) = aircraftRow.aircraft_category;
        adep(flightIndex) = departureAirport.icao;
        adepName(flightIndex) = departureAirport.name;
        depRunway(flightIndex) = chooseRunwayIdentifierLocal(chosenDepartureRunway);
        ades(flightIndex) = arrivalAirport.icao;
        adesName(flightIndex) = arrivalAirport.name;
        arrRunway(flightIndex) = chooseRunwayIdentifierLocal(chosenArrivalRunway);
        distanceKm(flightIndex) = candidateDistances(arrivalChoice);
        depLatitudeDeg(flightIndex) = departureAirport.latitude_deg;
        depLongitudeDeg(flightIndex) = departureAirport.longitude_deg;
        arrLatitudeDeg(flightIndex) = arrivalAirport.latitude_deg;
        arrLongitudeDeg(flightIndex) = arrivalAirport.longitude_deg;

        fprintf("--- DEBUG INFO for %s ---\n", flightId(flightIndex));
        fprintf("Aircraft %s requires Min Length: %.0f ft, Min Width: %.0f ft\n", ...
            aircraftRow.aircraft_type, aircraftRow.min_runway_length_ft, aircraftRow.min_runway_width_ft);
        fprintf("Departure Runway %s (Airport %s) has Length: %.0f ft, Width: %.0f ft\n", ...
            depRunway(flightIndex), adep(flightIndex), chosenDepartureRunway.length_ft, chosenDepartureRunway.width_ft);
        fprintf("Arrival Runway %s (Airport %s) has Length: %.0f ft, Width: %.0f ft\n", ...
            arrRunway(flightIndex), ades(flightIndex), chosenArrivalRunway.length_ft, chosenArrivalRunway.width_ft);
        fprintf("----------------------------\n\n");

        flightWasGenerated = true;
        break
    end

    if ~flightWasGenerated
        error("Could not generate flight %d within the current constraints.", flightIndex);
    end
end

flights = table( ...
    flightId, aircraftType, aircraftCategory, adep, adepName, depRunway, ...
    ades, adesName, arrRunway, distanceKm, ...
    depLatitudeDeg, depLongitudeDeg, arrLatitudeDeg, arrLongitudeDeg, ...
    'VariableNames', { ...
    'flight_id', 'aircraft_type', 'aircraft_category', 'adep', 'adep_name', 'dep_runway', ...
    'ades', 'ades_name', 'arr_runway', 'distance_km', ...
    'dep_latitude_deg', 'dep_longitude_deg', 'arr_latitude_deg', 'arr_longitude_deg'});
end


function airportIndices = findSupportingAirportsLocal(airportCatalog, aircraftRow)
airportIndices = [];

for i = 1:numel(airportCatalog)
    runwayMask = runwaySupportsAircraftLocal(airportCatalog(i).runways, aircraftRow);
    if any(runwayMask)
        airportIndices(end + 1) = i; %#ok<AGROW>
    end
end
end


%% Find arrival candidates function
% Arrival airports that satisfy the constraints

function [arrivalCandidates, candidateDistances] = findArrivalCandidatesLocal(airportCatalog, departureAirportIndex, aircraftRow, minDistanceKm, maxDistanceKm)
arrivalCandidates = [];
candidateDistances = [];
departureAirport = airportCatalog(departureAirportIndex);

for i = 1:numel(airportCatalog)
    if i == departureAirportIndex
        continue
    end

    arrivalAirport = airportCatalog(i);
    distanceKm = greatCircleKmLocal( ...
        departureAirport.latitude_deg, departureAirport.longitude_deg, ...
        arrivalAirport.latitude_deg, arrivalAirport.longitude_deg);

    if distanceKm < minDistanceKm || distanceKm > maxDistanceKm
        continue
    end

    runwayMask = runwaySupportsAircraftLocal(arrivalAirport.runways, aircraftRow);
    if ~any(runwayMask)
        continue
    end

    arrivalCandidates(end + 1) = i; %#ok<AGROW>
    candidateDistances(end + 1) = distanceKm; %#ok<AGROW>
end
end

%% Choose runway function

function runwayIdentifier = chooseRunwayIdentifierLocal(runwayRow)
availableIdentifiers = strings(0, 1);

if strlength(strtrim(runwayRow.le_ident)) > 0
    availableIdentifiers(end + 1) = runwayRow.le_ident; %#ok<AGROW>
end

if strlength(strtrim(runwayRow.he_ident)) > 0
    availableIdentifiers(end + 1) = runwayRow.he_ident; %#ok<AGROW>
end

if isempty(availableIdentifiers)
    runwayIdentifier = "UNKNOWN";
else
    runwayIdentifier = availableIdentifiers(randi(numel(availableIdentifiers)));
end
end


%% Plot flights on globe function
function plotFlightsOnGlobeLocal(flights)
if isempty(flights)
    warning("No flights available to plot.");
    return
end

if canUseSatelliteScenarioViewerLocal()
    plotFlightsInSatelliteScenarioLocal(flights);
elseif canUseGeographicGlobeLocal()
    plotFlightsOnGeographicGlobeLocal(flights);
else
    plotFlightsOnFallbackSphereLocal(flights);
end
end

% Check if satellite scenario viewer can be used
function tf = canUseSatelliteScenarioViewerLocal()
tf = exist('satelliteScenario', 'file') == 2 && ...
    exist('satelliteScenarioViewer', 'file') == 2 && ...
    exist('geoTrajectory', 'file') == 2 && ...
    exist('platform', 'file') == 2;
end

% Check if geographic globe can be used
function tf = canUseGeographicGlobeLocal()
tf = exist('geoglobe', 'file') == 2 && exist('geoplot3', 'file') == 2;
end

% Plot flights in satellite scenario
function plotFlightsInSatelliteScenarioLocal(flights)
startTime = datetime('now');
stopTime = startTime + minutes(60);
sampleTime = 60;

scenario = satelliteScenario(startTime, stopTime, sampleTime);
satelliteScenarioViewer(scenario);
airportLabels = unique([ ...
    compose("%s - %s", flights.adep, flights.adep_name); ...
    compose("%s - %s", flights.ades, flights.ades_name)]);

for i = 1:height(flights)
    depLat = flights.dep_latitude_deg(i);
    depLon = flights.dep_longitude_deg(i);
    arrLat = flights.arr_latitude_deg(i);
    arrLon = flights.arr_longitude_deg(i);

    [midLat, midLon] = geographicMidpointLocal(depLat, depLon, arrLat, arrLon);
    cruiseAltitudeM = 11000;

    waypoints = [ ...
        depLat, depLon, 0; ...
        midLat, midLon, cruiseAltitudeM; ...
        arrLat, arrLon, 0];

    timeOfArrival = [0, 1800, 3600];
    trajectory = geoTrajectory(waypoints, timeOfArrival, AutoPitch=true, AutoBank=true);

    platformName = char(compose("%s %s-%s", flights.flight_id(i), flights.adep(i), flights.ades(i)));
    aircraftPlatform = platform(scenario, trajectory, Name=platformName);

    aircraftPlatform.MarkerSize = 6;
    aircraftPlatform.ShowLabel = true;

    if mod(i, 3) == 1
        aircraftPlatform.MarkerColor = [0.85 0.2 0.2];
    elseif mod(i, 3) == 2
        aircraftPlatform.MarkerColor = [0 0.45 0.74];
    else
        aircraftPlatform.MarkerColor = [0.2 0.7 0.3];
    end
end

for i = 1:numel(airportLabels)
    labelText = airportLabels(i);
    matchingDeparture = find(compose("%s - %s", flights.adep, flights.adep_name) == labelText, 1);
    matchingArrival = find(compose("%s - %s", flights.ades, flights.ades_name) == labelText, 1);

    if ~isempty(matchingDeparture)
        labelLat = flights.dep_latitude_deg(matchingDeparture);
        labelLon = flights.dep_longitude_deg(matchingDeparture);
    else
        labelLat = flights.arr_latitude_deg(matchingArrival);
        labelLon = flights.arr_longitude_deg(matchingArrival);
    end

    airportPoint = geoTrajectory([labelLat, labelLon, 0; labelLat, labelLon, 0], [0, 3600]);
    airportPlatform = platform(scenario, airportPoint, Name=char(labelText));
    airportPlatform.MarkerSize = 4;
    airportPlatform.ShowLabel = true;
    airportPlatform.MarkerColor = [1 0.95 0.2];
end

play(scenario);
end


% Plot flights on geographic globe
function plotFlightsOnGeographicGlobeLocal(flights)
uif = uifigure('Name', 'ATM Flight Globe');
g = geoglobe(uif, Basemap="satellite", Terrain="none");

hold(g, 'on')

for i = 1:height(flights)
    depLat = flights.dep_latitude_deg(i);
    depLon = flights.dep_longitude_deg(i);
    arrLat = flights.arr_latitude_deg(i);
    arrLon = flights.arr_longitude_deg(i);

    [latArc, lonArc, heightArc] = buildGreatCircleTrackLocal(depLat, depLon, arrLat, arrLon);

    geoplot3(g, latArc, lonArc, heightArc, ...
        'LineWidth', 3, 'Color', [0.85 0.2 0.2]);

    geoplot3(g, depLat, depLon, 0, 'o', ...
        'MarkerSize', 8, ...
        'Color', [0 0.45 0.74]);

    geoplot3(g, arrLat, arrLon, 0, 'o', ...
        'MarkerSize', 8, ...
        'Color', [0.2 0.7 0.3]);
end

if height(flights) >= 1
    midLat = mean([flights.dep_latitude_deg(1), flights.arr_latitude_deg(1)]);
    midLon = mean([flights.dep_longitude_deg(1), flights.arr_longitude_deg(1)]);
    campos(g, midLat, midLon, 2.5e6)
    campitch(g, -55)
    camheading(g, 25)
end
end

% Build great circle track
function [latArc, lonArc, heightArc] = buildGreatCircleTrackLocal(depLat, depLon, arrLat, arrLon)
if exist('interpm', 'file') == 2
    [latArc, lonArc] = interpm([depLat; arrLat], [depLon; arrLon], 0.5, 'gc');
else
    latArc = linspace(depLat, arrLat, 100)';
    lonArc = linspace(depLon, arrLon, 100)';
end

numPoints = numel(latArc);
t = linspace(0, 1, numPoints)';
heightArc = 120000 * sin(pi * t);
end

% Geographic midpoint function
function [midLatDeg, midLonDeg] = geographicMidpointLocal(lat1Deg, lon1Deg, lat2Deg, lon2Deg)
lat1Rad = deg2rad(lat1Deg);
lon1Rad = deg2rad(lon1Deg);
lat2Rad = deg2rad(lat2Deg);
lon2Rad = deg2rad(lon2Deg);

bx = cos(lat2Rad) * cos(lon2Rad - lon1Rad);
by = cos(lat2Rad) * sin(lon2Rad - lon1Rad);

midLatRad = atan2( ...
    sin(lat1Rad) + sin(lat2Rad), ...
    sqrt((cos(lat1Rad) + bx)^2 + by^2));
midLonRad = lon1Rad + atan2(by, cos(lat1Rad) + bx);

midLatDeg = rad2deg(midLatRad);
midLonDeg = wrapTo180(rad2deg(midLonRad));
end

% Plot flights on fallback sphere
function plotFlightsOnFallbackSphereLocal(flights)
earthRadiusKm = 6371.0;
globeRadiusKm = earthRadiusKm;
arcRadiusKm = earthRadiusKm * 1.03;
numArcPoints = 100;

figure('Name', 'ATM Flight Globe', 'Color', 'w');
[xSphere, ySphere, zSphere] = sphere(120);
surf(globeRadiusKm * xSphere, globeRadiusKm * ySphere, globeRadiusKm * zSphere, ...
    'FaceColor', [0.75 0.85 0.95], ...
    'EdgeColor', 'none', ...
    'FaceAlpha', 0.95);

hold on
axis equal
grid on
xlabel('X (km)')
ylabel('Y (km)')
zlabel('Z (km)')
title('Generated Flights on 3D Globe')
view(40, 28)
camlight headlight
lighting gouraud
labelKeys = strings(0, 1);

for i = 1:height(flights)
    depLat = flights.dep_latitude_deg(i);
    depLon = flights.dep_longitude_deg(i);
    arrLat = flights.arr_latitude_deg(i);
    arrLon = flights.arr_longitude_deg(i);

    depPoint = latLonToCartesianLocal(depLat, depLon, globeRadiusKm);
    arrPoint = latLonToCartesianLocal(arrLat, arrLon, globeRadiusKm);
    arcPoints = greatCircleArcLocal(depLat, depLon, arrLat, arrLon, arcRadiusKm, numArcPoints);

    plot3(arcPoints(:, 1), arcPoints(:, 2), arcPoints(:, 3), ...
        'LineWidth', 1.8, 'Color', [0.85 0.2 0.2]);
    scatter3(depPoint(1), depPoint(2), depPoint(3), 60, [0 0.45 0.74], 'filled');
    scatter3(arrPoint(1), arrPoint(2), arrPoint(3), 60, [0.2 0.7 0.3], 'filled');

    labelKeys = addAirportLabelSphereLocal(depPoint, flights.adep(i), flights.adep_name(i), labelKeys);
    labelKeys = addAirportLabelSphereLocal(arrPoint, flights.ades(i), flights.ades_name(i), labelKeys);
end

hold off
end

% Add airport labels to the sphere
function updatedKeys = addAirportLabelSphereLocal(point, airportIcao, airportName, existingKeys)
labelKey = compose("%s|%s", airportIcao, airportName);
updatedKeys = existingKeys;

if any(existingKeys == labelKey)
    return
end

labelText = char(compose("%s - %s", airportIcao, airportName));
text(point(1), point(2), point(3), ['  ' labelText], ...
    'FontSize', 8, 'Color', [1 1 1], 'FontWeight', 'bold');
updatedKeys(end + 1) = labelKey; %#ok<AGROW>
end


% Convert latitude and longitude to Cartesian coordinates
function point = latLonToCartesianLocal(latitudeDeg, longitudeDeg, radiusKm)
latitudeRad = deg2rad(latitudeDeg);
longitudeRad = deg2rad(longitudeDeg);

x = radiusKm * cos(latitudeRad) * cos(longitudeRad);
y = radiusKm * cos(latitudeRad) * sin(longitudeRad);
z = radiusKm * sin(latitudeRad);

point = [x, y, z];
end

% Great circle arc function
function arcPoints = greatCircleArcLocal(lat1Deg, lon1Deg, lat2Deg, lon2Deg, radiusKm, numPoints)
startUnit = latLonToCartesianLocal(lat1Deg, lon1Deg, 1);
endUnit = latLonToCartesianLocal(lat2Deg, lon2Deg, 1);

dotProduct = dot(startUnit, endUnit);
dotProduct = max(min(dotProduct, 1), -1);
omega = acos(dotProduct);

if abs(omega) < 1e-10
    repeatedPoint = latLonToCartesianLocal(lat1Deg, lon1Deg, radiusKm);
    arcPoints = repmat(repeatedPoint, numPoints, 1);
    return
end

tValues = linspace(0, 1, numPoints);
arcPoints = zeros(numPoints, 3);

for k = 1:numPoints
    t = tValues(k);
    point = (sin((1 - t) * omega) / sin(omega)) * startUnit + ...
        (sin(t * omega) / sin(omega)) * endUnit;
    point = point / norm(point);
    arcPoints(k, :) = radiusKm * point;
end
end
