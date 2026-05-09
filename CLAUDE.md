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
| Colleague A | Python flight performance script (BADA calc, Plotly map) | Done — has bugs, untested |
| Colleague B | European airport filtering from `airports.csv` + random flight initialisation | In progress |
| Colleague C | GUI (target: MATLAB App Designer) | Pending |
| **User (team leader)** | MATLAB integration (`main.m`), arrival conflict detection (`.m` function), overall integration | In progress |

**Known overlap risk:** Colleague B's airport filtering and random flight initialisation may duplicate logic already in the Python script. Audit Python script before Colleague B writes new code.

---

## Architecture

```
main.m  (orchestrator)
  │
  ├─ calls: Python script  →  flight time calculation (BADA-based)
  ├─ calls: Colleague B's script  →  European airport list + random flight generation
  ├─ calls: conflict_detection.m  →  arrival conflict detection (to be written)
  └─ calls: GUI (MATLAB App Designer app)  →  display results
```

**Python ↔ MATLAB interface:** Not yet decided. Options are:
- `system('python ...')` in MATLAB — Python runs as a subprocess, communicates via files (e.g., CSV) or stdout
- MATLAB Python engine (`py.*`) — calls Python functions directly from MATLAB (requires compatible Python version)
- File-based handoff — Python writes results to a file; MATLAB reads it

This is a key integration decision to resolve early.

---

## Python Script

**File:** `Código team assignment ATM final com simulation.py`  
**Written by:** Colleague A. The user is not the author and has limited visibility into its internals.

**What it does (parsed from source):**
- Loads aircraft data from `BADA_OR_3.6++(komma_test).xls` (sheets: `36++AIRCRAFT_TYPES`, `36++AIRLINE_PROCEDURES`)
- Loads airport data from `airports.csv` (84,726 global airports — not filtered to Europe)
- Calculates great-circle distance via Haversine formula
- Calculates True Airspeed (TAS) using ISO 2533 atmosphere model with crossover altitude logic (switches between CAS-based and Mach-based speed depending on altitude)
- Computes flight time, scheduled/actual departure and arrival times, and delay propagation
- Generates an interactive 3D map via Plotly
- Exposes a CLI menu: specific flight (Option 1) or random global flight (Option 2)

**Known bugs:**
- Lines 227–228: `bada_file` incorrectly points to `airports.csv` instead of the BADA `.xls` file. Fix:
  ```python
  bada_file = r"<your path>\BADA_OR_3.6++(komma_test).xls"
  airports_file = r"<your path>\airports.csv"
  ```
- Library compatibility issues — script currently cannot run. Debug session pending.
- Airport pool is global; needs to be filtered to European airports per assignment spec.

**What it does NOT do (gaps vs. assignment spec):**
- No European airport filter
- No batch random flight generation (only generates one flight at a time)
- No arrival conflict detection

---

## Data Files

| File | Contents | Used by |
|------|----------|---------|
| `BADA_OR_3.6++(komma_test).xls` | Aircraft performance data — cruise speeds (V_CRU2, M_CRU) per aircraft type | Python script |
| `airports.csv` | 84,726 global airports with ICAO codes, lat/lon, type, country | Python script; Colleague B will filter this |
| `runways.csv` | 47,679 runway records | Not currently used |

---

## Running the Python Script

```bash
# Activate the virtual environment (must do this before running Python)
venv\Scripts\activate

# Run
python "Código team assignment ATM final com simulation.py"
```

Dependencies (install if venv is missing):
```bash
pip install pandas numpy plotly xlrd openpyxl python-dateutil
```

---

## Pending Decisions

- Python ↔ MATLAB interface method
- Arrival conflict time window (configurable parameter value)
- GUI feature scope
- Which additional features to implement beyond the base spec (expandability)
