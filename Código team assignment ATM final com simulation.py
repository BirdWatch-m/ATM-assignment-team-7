import pandas as pd
import math
import random
from datetime import datetime, timedelta
import os
import plotly.graph_objects as go

class FlightPerformanceCalculator:
    def __init__(self, bada_filepath, airports_filepath):
        """Initializes the calculator by loading BADA sheets and the Airports database."""
        print(f"Loading BADA databases from: {bada_filepath}")
        if not os.path.exists(bada_filepath):
            raise FileNotFoundError(f"ERROR: The file '{bada_filepath}' was not found!")
            
        # Reads the BADA Excel files
        self.df_types = pd.read_excel(bada_filepath, sheet_name='36++AIRCRAFT_TYPES', engine='xlrd')
        self.df_procs = pd.read_excel(bada_filepath, sheet_name='36++AIRLINE_PROCEDURES', engine='xlrd')
        self.df_types['AIRCRAFT_TYPEID'] = self.df_types['AIRCRAFT_TYPEID'].astype(str).str.strip()
        
        print(f"Loading Airports database from: {airports_filepath}")
        if not os.path.exists(airports_filepath):
            raise FileNotFoundError(f"ERROR: The file '{airports_filepath}' was not found!")
        
        # Reads the Airports CSV
        self.df_airports = pd.read_csv(airports_filepath)
        print("All databases loaded successfully!\n")

    def get_airport_data(self, icao_code):
        """Retrieves latitude, longitude, and name for a given airport ICAO code."""
        icao_code = str(icao_code).strip().upper()
        airport = self.df_airports[(self.df_airports['ident'] == icao_code) | (self.df_airports['icao_code'] == icao_code)]
        
        if airport.empty:
            raise ValueError(f"Airport '{icao_code}' not found in the database.")
        
        lat = airport.iloc[0]['latitude_deg']
        lon = airport.iloc[0]['longitude_deg']
        name = airport.iloc[0]['name']
        return lat, lon, name

    def get_random_global_airports(self):
        """Selects two random, distinct global airports (Medium/Large only) for the simulation."""
        # Filters large and medium airports WORLDWIDE
        global_airports = self.df_airports[self.df_airports['type'].isin(['large_airport', 'medium_airport'])]
        
        if global_airports.empty:
            raise ValueError("No airports found in the database! Check your CSV format.")
            
        valid_icaos = global_airports['ident'].dropna().tolist()
        adep = random.choice(valid_icaos)
        ades = random.choice(valid_icaos)
        
        # Ensures origin and destination are not the same airport
        while ades == adep:
            ades = random.choice(valid_icaos)
            
        return adep, ades

    def get_supported_aircraft(self):
        """Returns a list of all supported aircraft in the BADA file."""
        return self.df_types['AIRCRAFT_TYPEID'].unique().tolist()

    def get_random_aircraft(self):
        """Returns a random aircraft from the BADA database."""
        return random.choice(self.get_supported_aircraft())

    def get_aircraft_cruise_speeds(self, aircraft_icao):
        """Finds the Calibrated Airspeed (V_CRU2) and Cruise Mach (M_CRU)."""
        aircraft_icao = str(aircraft_icao).strip().upper()
        aircraft = self.df_types[self.df_types['AIRCRAFT_TYPEID'] == aircraft_icao]
        
        if aircraft.empty:
            raise ValueError(f"Aircraft '{aircraft_icao}' not found in BADA.")
        
        pattern_id = aircraft.iloc[0]['PATTERN_TYPEID']
        proc = self.df_procs[self.df_procs['PATTERN_TYPEID'] == pattern_id]
        
        if proc.empty:
            raise ValueError(f"Procedures not found for Pattern ID {pattern_id}.")
            
        return proc.iloc[0]['V_CRU2'], proc.iloc[0]['M_CRU']

    def calculate_tas(self, v_cru2_kts, m_cru, flight_level):
        """Calculates True Airspeed (TAS) considering the Crossover Altitude logic."""
        altitude_ft = flight_level * 100
        
        if altitude_ft <= 36089:
            temp_k = 288.15 - (0.0019812 * altitude_ft)
            delta = (1 - 0.00000687559 * altitude_ft) ** 5.25588
        else:
            temp_k = 216.65
            delta = 0.22336 * math.exp(-0.0000480634 * (altitude_ft - 36089))
            
        speed_of_sound_local = 38.96785 * math.sqrt(temp_k)
        tas_mach = m_cru * speed_of_sound_local
        
        a0 = 661.4786
        term1 = 1 + 0.2 * ((v_cru2_kts / a0) ** 2)
        term2 = ((term1 ** 3.5) - 1) / delta
        mach_from_cas = math.sqrt(5 * ((term2 + 1) ** (1/3.5) - 1))
        tas_cas = mach_from_cas * speed_of_sound_local
        
        if tas_cas < tas_mach:
            return tas_cas, "CAS (Low/Medium Altitude)"
        else:
            return tas_mach, "MACH (High Altitude)"
        
    def haversine_distance(self, lat1, lon1, lat2, lon2):
        """Calculates the orthodromic (great-circle) distance in Nautical Miles (NM)."""
        R_NM = 3440.065
        phi1, phi2 = math.radians(lat1), math.radians(lat2)
        delta_phi = math.radians(lat2 - lat1)
        delta_lambda = math.radians(lon2 - lon1)
        
        a = math.sin(delta_phi/2.0)**2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda/2.0)**2
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
        return R_NM * c

    def calculate_flight(self, adep_icao, ades_icao, aircraft_icao, flight_level, std, dep_delay_mins=0, enroute_delay_mins=0):
        """Calculates flight details including schedules and delays."""
        lat1, lon1, adep_name = self.get_airport_data(adep_icao)
        lat2, lon2, ades_name = self.get_airport_data(ades_icao)
        
        v_cru2, m_cru = self.get_aircraft_cruise_speeds(aircraft_icao)
        tas, speed_profile = self.calculate_tas(v_cru2, m_cru, flight_level)
        
        distance_nm = self.haversine_distance(lat1, lon1, lat2, lon2)
        time_hours = distance_nm / tas
        ideal_flight_duration = timedelta(hours=time_hours)
        
        sta = std + ideal_flight_duration 
        actual_flight_duration = ideal_flight_duration + timedelta(minutes=enroute_delay_mins)
        atd = std + timedelta(minutes=dep_delay_mins) 
        ata = atd + actual_flight_duration 
        total_arrival_delay = (ata - sta).total_seconds() / 60.0
        
        return {
            "adep_icao": adep_icao, "adep_name": adep_name, "lat1": lat1, "lon1": lon1,
            "ades_icao": ades_icao, "ades_name": ades_name, "lat2": lat2, "lon2": lon2,
            "aircraft": aircraft_icao, "flight_level": flight_level,
            "distance_nm": distance_nm, "tas_kts": tas, "speed_profile": speed_profile,
            "ideal_flight_duration": ideal_flight_duration,
            "std": std, "atd": atd, "departure_delay_mins": dep_delay_mins,
            "sta": sta, "ata": ata, "enroute_delay_mins": enroute_delay_mins,
            "total_arrival_delay_mins": total_arrival_delay
        }

    def print_flight_report(self, res):
        """Prints a detailed and clean report ONLY to the terminal."""
        hours, remainder = divmod(res['ideal_flight_duration'].total_seconds(), 3600)
        minutes = remainder // 60
        time_str = f"{int(hours)}h {int(minutes)}m"

        print("\n" + "="*55)
        print(f" FLIGHT REPORT: {res['adep_icao']} -> {res['ades_icao']}")
        print("="*55)
        print(f" Aircraft:      {res['aircraft']} at FL{res['flight_level']}")
        print(f" Route:         {res['adep_name']} to {res['ades_name']}")
        print(f" Distance:      {res['distance_nm']:.2f} NM")
        print(f" Speed Profile: {res['speed_profile']} (TAS: {res['tas_kts']:.2f} kts)")
        print(f" Flight Time:   {time_str}")
        print("-" * 55)
        print(" DEPARTURE TIMINGS")
        print(f"   STD (Scheduled):  {res['std'].strftime('%H:%M')}")
        print(f"   ATD (Actual):     {res['atd'].strftime('%H:%M')}")
        print(f"   Delay:            +{res['departure_delay_mins']} mins")
        print("-" * 55)
        print(" ARRIVAL TIMINGS")
        print(f"   STA (Scheduled):  {res['sta'].strftime('%H:%M')}")
        print(f"   ATA (Actual):     {res['ata'].strftime('%H:%M')}")
        print(f"   En-route Delay:   +{res['enroute_delay_mins']} mins")
        print(f"   TOTAL DELAY:      +{res['total_arrival_delay_mins']:.0f} mins")
        print("="*55 + "\n")

    def plot_trajectory(self, flight_data):
        """Generates a clean 3D globe with only the route and the map."""
        print("[!] Opening 3D map viewer in your browser...")
        fig = go.Figure()

        # Adiciona a linha de voo ortodrómica
        fig.add_trace(go.Scattergeo(
            lon = [flight_data['lon1'], flight_data['lon2']],
            lat = [flight_data['lat1'], flight_data['lat2']],
            mode = 'lines',
            line = dict(width = 3, color = 'red'),
            name = "Flight Route"
        ))

        # Adiciona os pontos de partida e chegada
        fig.add_trace(go.Scattergeo(
            lon = [flight_data['lon1'], flight_data['lon2']],
            lat = [flight_data['lat1'], flight_data['lat2']],
            mode = 'markers+text',
            text = [flight_data['adep_icao'], flight_data['ades_icao']],
            textposition = "bottom center",
            marker = dict(size = 8, color = 'blue', line=dict(width=1, color='black')),
            name = 'Airports',
            hoverinfo = 'text'
        ))

        mid_lon = (flight_data['lon1'] + flight_data['lon2']) / 2
        mid_lat = (flight_data['lat1'] + flight_data['lat2']) / 2

        fig.update_layout(
            title_text = f"Flight Route: {flight_data['adep_icao']} ➔ {flight_data['ades_icao']}",
            title_x = 0.5,
            showlegend = False,
            margin = dict(t=50, b=0, l=0, r=0),
            geo = dict(
                projection_type = 'orthographic',
                showland = True,
                landcolor = 'rgb(243, 243, 243)',
                countrycolor = 'rgb(204, 204, 204)',
                showocean = True,
                oceancolor = 'rgb(204, 229, 255)',
                showcountries = True,
                center = dict(lon = mid_lon, lat = mid_lat)
            )
        )
        fig.show()

# =========================================================
# Testing Interface
# =========================================================
if __name__ == "__main__":
    # SET YOUR ABSOLUTE FILE PATHS HERE
    bada_file =  r"D:\HomeWork\Year 4 Sem 2\ATM\Group Project\BADA_OR_3.6++(komma_test).xls"
    airports_file = r"D:\HomeWork\Year 4 Sem 2\ATM\Group Project\airports.csv"
    
    try:
        calc = FlightPerformanceCalculator(bada_file, airports_file)
        
        while True:
            print("\n--- GLOBAL FLIGHT SIMULATOR ---")
            print("1. Calculate a specific flight")
            print("2. Generate a RANDOM GLOBAL flight")
            print("3. Exit")
            
            choice = input("Choose an option (1/2/3): ")
            
            if choice == '1':
                adep = input("Enter Departure Airport ICAO (e.g., KJFK): ").upper()
                ades = input("Enter Destination Airport ICAO (e.g., RJTT): ").upper()
                aircraft = input("Enter Aircraft ICAO (e.g., B77W): ").upper()
                fl = int(input("Enter Flight Level (e.g., 350): "))
                
                std_input = input("Enter Scheduled Departure Time (YYYY-MM-DD HH:MM) or press Enter for 'now': ")
                if std_input.strip() == "":
                    std = datetime.now().replace(second=0, microsecond=0)
                else:
                    std = datetime.strptime(std_input, "%Y-%m-%d %H:%M")
                    
                dep_delay = int(input("Enter Departure Delay (minutes): "))
                enroute_delay = int(input("Enter En-route/Holding Delay (minutes): "))
                
                try:
                    res = calc.calculate_flight(adep, ades, aircraft, fl, std, dep_delay, enroute_delay)
                    # 1: Print report to terminal
                    calc.print_flight_report(res)
                    # 2: Pause so user can read the report
                    input("👉 Press [ENTER] to open the clean 3D map viewer...")
                    # 3: Open 3D map in browser
                    calc.plot_trajectory(res)
                except ValueError as e:
                    print(f"\n[ERROR] {e}")
                    
            elif choice == '2':
                try:
                    print("\n[!] Processing random global flight...")
                    adep, ades = calc.get_random_global_airports()
                    aircraft = calc.get_random_aircraft()
                    fl = random.randint(300, 400)
                    
                    base_time = datetime.now().replace(second=0, microsecond=0)
                    random_std = base_time + timedelta(minutes=random.randint(0, 120))
                    random_dep_delay = random.choice([0, 0, 0, 15, 30]) 
                    random_enr_delay = random.choice([0, 0, 10, 20])
                    
                    res = calc.calculate_flight(adep, ades, aircraft, fl, random_std, random_dep_delay, random_enr_delay)
                    
                    # 1: Print report to terminal
                    calc.print_flight_report(res)
                    # 2: Pause so user can read the report
                    input("👉 Press [ENTER] to open the clean 3D map viewer...")
                    # 3: Open 3D map in browser
                    calc.plot_trajectory(res)
                except ValueError as e:
                    print(f"\n[ERROR] {e}")

            elif choice == '3':
                print("Exiting simulator...")
                break
            else:
                print("Invalid option. Please try again.")

    except Exception as e:
        print(f"Error starting the program: {e}")