# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Working with This User

- Use technical language; explain any moderate or advanced terms inline where they appear.
- Be brief. No filler or descriptive adjectives.
- Ask clarifying questions before proceeding when requirements are ambiguous.
- The user (team leader) has 0 Python experience and limited general programming background. Assume no Python knowledge when explaining Python-related issues.

---

## Assignment: Subject 7 – Network Traffic Generator

**Core requirements:**
1. Generate random flights between European airport pairs (ADEP/ADES)
2. Assign random departure times, random cruise flight level, random aircraft type
3. Calculate arrival time (great-circle/orthodrome route, constant cruise speed using BADA parameters)
4. Detect and display arrival conflicts — flights arriving at the same ADES within a configurable time window
5. Output via interactive GUI showing the simulation and results

**Expandability** is an explicit grading criterion. The basic spec is the minimum; additional features are expected if time permits. Architecture decisions should keep this in mind.

---

## Team Structure & Responsibilities

| Member | Responsibility | Status |
|--------|---------------|--------|
| Colleague A | Python flight performance script (BADA calc, Plotly map) | **Retired from integration** — logic ported to MATLAB |
| Colleague B | European airport filtering + random flight initialisation | **Absorbed into `main_flight_generation.m`** |
| Colleague C | GUI (target: MATLAB App Designer) | Pending |
| **User (team leader)** | `main_flight_generation.m`, arrival conflict detection, overall integration | In progress |

---

## Architecture

```
main_flight_generation.m  (current working script — will be split or called from main.m)
  │
  ├─ loadAirportDataLocal          →  reads airports.csv + runways.csv
  ├─ getAircraftDatabaseLocal      →  reads Aircraft_BADA_Mapping.csv (single source of truth)
  ├─ buildAirportRunwayCatalogLocal→  filters EU large/medium airports; pairs with usable runways
  ├─ buildDistanceMatrixLocal      →  precomputes 741×741 pairwise NM distance matrix (run once)
  ├─ generateRandomFlightsLocal    →  generates N flights; assigns aircraft, airports, FL, flight time
  ├─ computeFlightTimeLocal        →  ISA atmosphere + crossover altitude → TAS → flight time (hrs)
  ├─ conflict_detection.m          →  arrival conflict detection (TO BE WRITTEN)
  └─ GUI (MATLAB App Designer)     →  display results (TO BE WRITTEN — Colleague C)
```

**Python is no longer part of the integration path.** All BADA-based calculations are now in MATLAB. The Python script is retained as a reference only.

**Unit standard: NM everywhere** for distances. Flight levels in hundreds of feet (e.g. FL350 = integer 350). Time in hours.

---

## Python Script

**File:** `Código team assignment ATM final com simulation.py`
**Status: RETIRED from integration.** Logic has been ported to MATLAB. Keep as reference only.

**Why retired:** Python ↔ MATLAB interop (subprocess / `py.*` engine / file handoff) adds latency and failure modes that are unacceptable for thousands-of-flights simulation runs. All required functionality now exists natively in MATLAB.

---

## Data Files

| File | Contents | Used by |
|------|----------|---------|
| `BADA_OR_3.6++(komma_test).xls` | Original BADA source — **runtime dependency removed**; used only to build the CSV | Reference only |
| `Aircraft_BADA_Mapping.csv` | **Single source of truth for all aircraft data** — 72 aircraft with BADA-verified performance data | `main_flight_generation.m` |
| `airports.csv` | 84,726 global airports with ICAO codes, lat/lon, type, country | `main_flight_generation.m` (filtered to EU large/medium at runtime) |
| `runways.csv` | 47,679 runway records | `main_flight_generation.m` |

### Aircraft_BADA_Mapping.csv — column reference

| Column | Type | Notes |
|--------|------|-------|
| `Aircraft Type` | string | Full name (display only) |
| `Category` | string | `local_aircraft`, `regional`, `medium_range`, `long_range`, `cargo` |
| `BADA ID` | string | ICAO aircraft type designator — **key for BADA lookup** |
| `Min Runway Length (ft)` | number | Minimum runway length required |
| `Min Runway Width (m)` | number | Source width; converted to ft internally |
| `Min Runway Width (ft)` | number | Used directly if present |
| `ICAO Code (runway)` | string | Runway category code |
| `Range (km)` | number | Informational only |
| `V_CRU2_kts` | number | Cruise CAS (calibrated airspeed) in knots — from `36++AIRLINE_PROCEDURES` |
| `M_CRU` | number | Cruise Mach number — from `36++AIRLINE_PROCEDURES` |
| `wake_turb_cat` | string | ICAO wake turbulence category: L/M/H/J — from `36++AIRCRAFT_PATTERNS` |
| `h_mo_ft` | number | Maximum operating altitude in feet — from `36++AIRCRAFT_PATTERNS`; caps FL draw |

**72 rows — all have direct BADA 3.6++ match. 25 rows were dropped (post-2010 aircraft not in BADA 3.6++): B77W, B788, B789, A35K, A358, A359, A388, B748, BCS1, BCS3, E175, CRJX, DHC6, MRJ7, SU95, A148, T334, B783, A225, B77L (+ cargo variants).**

---

## main_flight_generation.m — function reference

| Function | Inputs | Outputs | Notes |
|----------|--------|---------|-------|
| `loadAirportDataLocal` | filenames | `airportsTable`, `runwaysTable` | Forces numeric types on runway columns |
| `getAircraftDatabaseLocal` | filename | `aircraftTable` | Reads all 9 performance columns from CSV |
| `buildAirportRunwayCatalogLocal` | tables | `airportCatalog` (1×741 struct) | EU + large/medium + ICAO + coordinates + ≥1 usable runway |
| `buildDistanceMatrixLocal` | `airportCatalog` | `distanceMatrix` (741×741 double, NM) | Computed once at startup; upper triangle only, mirrored |
| `greatCircleNmLocal` | lat1,lon1,lat2,lon2 | `distanceNm` | Haversine; Earth radius 3440.065 NM |
| `computeFlightTimeLocal` | `distanceNm`, `vCru2Kts`, `mCru`, `flightLevel` | `flightTimeHours` | ISA atmosphere model; crossover altitude logic |
| `generateRandomFlightsLocal` | catalog, matrix, aircraftTable, N, minNm, maxNm | `flights` table | Up to 250 attempts per flight; errors if exhausted |
| `findSupportingAirportsLocal` | catalog, aircraftRow | index array | Airports with ≥1 runway supporting the aircraft |
| `findArrivalCandidatesLocal` | matrix, depIdx, aircraftRow, catalog, minNm, maxNm | index array, distance array | Distance filter from matrix; runway check |
| `runwaySupportsAircraftLocal` | runwayTable, aircraftRow | boolean mask | length ≥ min AND width ≥ min AND open |
| `chooseRunwayIdentifierLocal` | runwayRow | string | Picks randomly from le_ident / he_ident |
| `plotFlightsOnGlobeLocal` | `flights` | — | Tries satelliteScenario → geoglobe → fallback sphere |

### flights table — column reference

| Column | Type | Notes |
|--------|------|-------|
| `flight_id` | string | `F001`, `F002`, … |
| `aircraft_type` | string | Full name |
| `aircraft_category` | string | |
| `bada_id` | string | ICAO designator |
| `adep` | string | Departure ICAO |
| `adep_name` | string | |
| `dep_runway` | string | |
| `ades` | string | Arrival ICAO |
| `ades_name` | string | |
| `arr_runway` | string | |
| `distance_nm` | double | Great-circle distance |
| `flight_level` | double | Random integer in [100, floor(h_mo_ft/100)] |
| `flight_time_hours` | double | From `computeFlightTimeLocal` |
| `dep_latitude_deg` | double | |
| `dep_longitude_deg` | double | |
| `arr_latitude_deg` | double | |
| `arr_longitude_deg` | double | |

---

## Pending

- Random departure time assignment (missing from flights table)
- Arrival time = departure time + flight_time_hours (needed before conflict detection)
- `conflict_detection.m` — arrival conflict detection; time window is a configurable parameter
- GUI feature scope (Colleague C)
- Which additional features beyond base spec (expandability criterion)
