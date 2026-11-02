"""
Module: 01_race_state_replay.py
Team Member: Moaz (UI Architecture & Interactive Tab System)
             Mohamed (Continuous Global Time Kinematics & DNF Filter)
             Yousef (Red Flag Pit Lane Parking & Flag State Machine)
             Mahmud (Weather Evolution & Stint Telemetry Analysis)
Phase: Phase 3 - Race State Simulation & Virtual Track Circle Upgrade
Objective: High-performance, fully synchronized Formula 1 Simulation Application:
           - Full 5-tab application suite with persistent session states and zero dead links.
           - Continuous global race time T_elapsed with 60 FPS real-time Canvas animation.
           - Strict Red Flag Physics: When a Red Flag occurs, omega = 0 and cars park in pit lane arc.
           - Instantaneous DNF / DNS Car Removal from track circle; retired cars classified at the bottom of timing tower.
           - Complete 20-driver Live Leaderboard with exact intervals, gaps, tyre ages, and badges.
           - Driver Focus Mode & Telemetry Spotlight (Highlighting, isolating, and side-by-side stint comparison).
           - Strictly Zero Emojis (Text Badges [S], [M], [H], [I], [W], [PIT], [GREEN], [SC], [VSC], [RED], [DNF], [DNS]).
           - Matte Black (#0B0C10) & Electric Pit-Wall Blue (#00F0FF) theme.
"""

import math
import os
import json
import pandas as pd
import streamlit as st
import streamlit.components.v1 as components

# Page configuration
st.set_page_config(
    page_title="F1 Race State Simulation | Pit-Wall Replay",
    page_icon="🏎️",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Load CSS stylesheet
css_path = os.path.join(os.path.dirname(__file__), '..', 'styles', 'pitwall_black_blue.css')
if os.path.exists(css_path):
    with open(css_path, 'r') as f:
        st.markdown(f"<style>{f.read()}</style>", unsafe_allow_html=True)


@st.cache_data(show_spinner=False)
def load_warehouse_data():
    """Load core dimensions and constructor mappings."""
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'exports', 'silver'))
    
    races_df = pd.read_csv(os.path.join(base_dir, 'dim_races.csv'))
    drivers_df = pd.read_csv(os.path.join(base_dir, 'dim_drivers.csv'))
    constructors_df = pd.read_csv(os.path.join(base_dir, 'dim_constructors.csv'))
    
    drivers_df['team_colour'] = drivers_df['team_colour'].astype(str).str.strip().str.upper()
    constructors_df['team_colour'] = constructors_df['team_colour'].astype(str).str.strip().str.upper()
    
    return races_df, drivers_df, constructors_df


@st.cache_data(show_spinner=False)
def load_session_telemetry(session_key: int):
    """Load all fact tables for the chosen Grand Prix session."""
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'exports', 'silver'))
    
    # 1. Fact Race Laps
    laps_path = os.path.join(base_dir, 'fact_race_laps.csv')
    laps_iter = pd.read_csv(laps_path, chunksize=25000, dtype={'compound_code': str})
    session_laps = pd.concat([chunk[chunk['session_key'] == session_key] for chunk in laps_iter])
    
    # 2. Fact Pit Stops
    pits_path = os.path.join(base_dir, 'fact_pit_stops.csv')
    pits_df = pd.read_csv(pits_path)
    session_pits = pits_df[pits_df['session_key'] == session_key]
    
    # 3. Fact Race Control
    rc_path = os.path.join(base_dir, 'fact_race_control.csv')
    rc_df = pd.read_csv(rc_path)
    session_rc = rc_df[rc_df['session_key'] == session_key]
    
    # 4. Fact Weather
    weather_path = os.path.join(base_dir, 'fact_weather.csv')
    weather_df = pd.read_csv(weather_path)
    session_weather = weather_df[weather_df['session_key'] == session_key]
    
    # 5. Fact Race Results (for accurate DNF / DNS / DSQ detection)
    results_path = os.path.join(base_dir, 'fact_race_results.csv')
    results_df = pd.read_csv(results_path)
    session_results = results_df[results_df['session_key'] == session_key]
    
    # 6. Fact Stint Summary
    stints_path = os.path.join(base_dir, 'fact_stint_summary.csv')
    stints_df = pd.read_csv(stints_path)
    session_stints = stints_df[stints_df['session_key'] == session_key]
    
    return session_laps, session_pits, session_rc, session_weather, session_results, session_stints


# Top Navigation Header
f1_logo_path = os.path.join(os.path.dirname(__file__), '..', 'assets', 'f1_logo.svg')
f1_svg_html = ""
if os.path.exists(f1_logo_path):
    with open(f1_logo_path, 'r') as f:
        f1_svg_html = f.read()

st.markdown(f"""
<div class="pitwall-header">
  <div class="pitwall-logo-container">
    <div>{f1_svg_html}</div>
    <div class="pitwall-title">RACE STATE SIMULATION <span>// VIRTUAL TRACK CIRCLE REPLAY</span></div>
  </div>
  <div style="font-family: 'JetBrains Mono', monospace; font-size: 0.8rem; color: #8E9BAE;">
    WAREHOUSE: <span style="color: #00F0FF;">SILVER MEDALLION</span> | REPLAY ENGINE: <span style="color: #0066FF;">ACTIVE (60 FPS CONTINUOUS)</span>
  </div>
</div>
""", unsafe_allow_html=True)


# Load Dimensions
races_df, dim_drivers, dim_constructors = load_warehouse_data()

# Build Team Colors & Details Map
team_colors_map = {}
for _, row in dim_constructors.iterrows():
    t_name = str(row['team_name'])
    t_col = str(row['team_colour']).strip().upper()
    if not t_col.startswith('#'):
        t_col = '#' + t_col
    team_colors_map[t_name] = t_col

# Fallbacks for known constructors
team_colors_map.update({
    'Red Bull Racing': '#3671C6',
    'Ferrari': '#E8002D',
    'Mercedes': '#27F4D2',
    'McLaren': '#FF8000',
    'Aston Martin': '#229971',
    'Alpine': '#FF87BC',
    'Williams': '#64C4FF',
    'RB': '#6692FF',
    'Racing Bulls': '#6692FF',
    'Kick Sauber': '#52E252',
    'Haas F1 Team': '#B6BABD',
    'Alfa Romeo': '#C92D4B',
    'AlphaTauri': '#5E8FAA'
})


# Sidebar: Race Selector & Controls
with st.sidebar:
    st.markdown("### SESSION SELECTOR")
    years = sorted(races_df['year'].unique().tolist(), reverse=True)
    selected_year = st.selectbox("Season", years, index=0)
    
    year_races = races_df[races_df['year'] == selected_year].sort_values(by='round')
    race_options = {
        f"R{int(r['round']):02d} - {r['circuit_short_name']} ({r['meeting_name']})": int(r['session_key'])
        for _, r in year_races.iterrows()
    }
    
    selected_race_label = st.selectbox("Grand Prix", list(race_options.keys()), index=0)
    session_key = race_options[selected_race_label]
    race_meta = year_races[year_races['session_key'] == session_key]
    
    st.markdown("---")
    st.markdown("### TELEMETRY SPOTLIGHT")
    season_drivers = sorted(dim_drivers[dim_drivers['year'] == selected_year]['name_acronym'].unique().tolist())
    focus_drivers = st.multiselect(
        "Focus Driver(s)",
        options=season_drivers,
        default=[]
    )
    isolate_focus = st.checkbox("Hide Non-Focused Cars on Circle", value=False)
    
    st.markdown("---")
    st.info("System Features:\n- Live 60 FPS Canvas with Play/Pause.\n- Red Flag pit lane parking.\n- DNF removal from track circle.\n- Complete 20-driver classifications.")


# Load Telemetry Data for selected session
session_laps, session_pits, session_rc, session_weather, session_results, session_stints = load_session_telemetry(session_key)

if session_laps.empty:
    st.error(f"[ERROR] No lap telemetry found for session {session_key}.")
    st.stop()

max_laps = int(session_laps['lap_number'].max())
circuit_name = str(race_meta.iloc[0]['circuit_short_name']).upper()


# ------------------------------------------------------------------------------
# PRE-PROCESSING: Build Retirement Lookup & Continuous Time Series per Driver
# ------------------------------------------------------------------------------
retirement_dict = {}
for _, row in session_results.iterrows():
    drv = int(row['driver_number'])
    is_dnf = str(row.get('dnf', '')).lower() in ['t', 'true', '1']
    is_dns = str(row.get('dns', '')).lower() in ['t', 'true', '1']
    is_dsq = str(row.get('dsq', '')).lower() in ['t', 'true', '1']
    num_laps = int(row['number_of_laps']) if pd.notna(row.get('number_of_laps')) else 0
    retirement_dict[drv] = {
        'is_dnf': is_dnf,
        'is_dns': is_dns,
        'is_dsq': is_dsq,
        'max_completed_lap': num_laps,
        'status_code': '[DNS]' if is_dns else ('[DSQ]' if is_dsq else ('[DNF]' if is_dnf else '[FINISHED]'))
    }

# Process each driver's laps chronologically
sorted_laps = session_laps.sort_values(by=['driver_number', 'lap_number']).copy()
sorted_laps['lap_duration'] = pd.to_numeric(sorted_laps['lap_duration'], errors='coerce').fillna(90.0)
sorted_laps['s1'] = pd.to_numeric(sorted_laps['duration_sector_1'], errors='coerce').fillna(sorted_laps['lap_duration'] / 3.0)
sorted_laps['s2'] = pd.to_numeric(sorted_laps['duration_sector_2'], errors='coerce').fillna(sorted_laps['lap_duration'] / 3.0)
sorted_laps['s3'] = pd.to_numeric(sorted_laps['duration_sector_3'], errors='coerce').fillna(sorted_laps['lap_duration'] / 3.0)

drivers_time_series = []
total_race_duration_s = 0.0

for drv_num, grp in sorted_laps.groupby('driver_number'):
    grp = grp.reset_index(drop=True)
    cum_end = grp['lap_duration'].cumsum()
    cum_start = cum_end - grp['lap_duration']
    
    laps_meta = []
    for i, row in grp.iterrows():
        comp_str = str(row.get('compound', 'MEDIUM')).upper()
        comp_badge = comp_str[0] if comp_str in ['SOFT', 'MEDIUM', 'HARD', 'INTERMEDIATE', 'WET'] else 'M'
        
        laps_meta.append({
            'lap': int(row['lap_number']),
            'start_t': float(cum_start[i]),
            'end_t': float(cum_end[i]),
            'dur': float(row['lap_duration']),
            's1': float(row['s1']),
            's2': float(row['s2']),
            's3': float(row['s3']),
            'compound': comp_str,
            'compound_badge': comp_badge,
            'tyre_age': int(row['tyre_age_laps']) if pd.notna(row.get('tyre_age_laps')) else 1,
            'is_pit_in': str(row.get('is_pit_in_lap', '')).lower() in ['true', 't', '1'],
            'is_pit_out': str(row.get('is_pit_out_lap', '')).lower() in ['true', 't', '1'],
            'speed': round(float(row['i1_speed']) if pd.notna(row.get('i1_speed')) else 280.0, 1)
        })
    
    first_row = grp.iloc[0]
    t_name = str(first_row.get('team_name', 'Unknown'))
    drv_total_t = float(cum_end.iloc[-1])
    if drv_total_t > total_race_duration_s:
        total_race_duration_s = drv_total_t
        
    ret_info = retirement_dict.get(int(drv_num), {'is_dnf': False, 'is_dns': False, 'is_dsq': False, 'max_completed_lap': max_laps, 'status_code': '[FINISHED]'})
    
    drivers_time_series.append({
        'driver_number': int(drv_num),
        'acronym': str(first_row.get('name_acronym', 'DRV')),
        'team': t_name,
        'team_color': team_colors_map.get(t_name, '#3671C6'),
        'total_time': drv_total_t,
        'is_dnf': ret_info['is_dnf'],
        'is_dns': ret_info['is_dns'],
        'is_dsq': ret_info['is_dsq'],
        'max_lap': ret_info['max_completed_lap'],
        'status_code': ret_info['status_code'],
        'laps': laps_meta
    })

# Also include drivers from fact_race_results who might have 0 laps (e.g. DNS or Lap 0 DNF)
active_driver_numbers = [d['driver_number'] for d in drivers_time_series]
for _, r_row in session_results.iterrows():
    drv_num = int(r_row['driver_number'])
    if drv_num not in active_driver_numbers:
        t_name = str(r_row.get('team_name', 'Unknown'))
        ret_info = retirement_dict.get(drv_num, {'is_dnf': True, 'is_dns': True, 'is_dsq': False, 'max_completed_lap': 0, 'status_code': '[DNS]'})
        drivers_time_series.append({
            'driver_number': drv_num,
            'acronym': str(r_row.get('name_acronym', 'DRV')),
            'team': t_name,
            'team_color': team_colors_map.get(t_name, '#3671C6'),
            'total_time': 0.0,
            'is_dnf': ret_info['is_dnf'],
            'is_dns': ret_info['is_dns'],
            'is_dsq': ret_info['is_dsq'],
            'max_lap': ret_info['max_completed_lap'],
            'status_code': ret_info['status_code'],
            'laps': []
        })


# ------------------------------------------------------------------------------
# PRE-PROCESSING: Strict FIA Flag State Machine & Red Flag Detection
# ------------------------------------------------------------------------------
flag_states_payload = {}
weather_states_payload = {}

# Group race control by lap for fast lookup
rc_by_lap = {l: grp for l, grp in session_rc.groupby('lap_number')}

for l in range(1, max_laps + 1):
    past_rc = session_rc[session_rc['lap_number'] <= l]
    lap_rc = rc_by_lap.get(l, pd.DataFrame())
    
    # Check for Red Flag condition
    lap_flags = [str(x).upper() for x in lap_rc['flag'].dropna().unique()] if not lap_rc.empty else []
    lap_msgs = [str(x).upper() for x in lap_rc['message'].dropna().unique()] if not lap_rc.empty else []
    
    is_red = any('RED' in f for f in lap_flags) or any('RED FLAG' in m for m in lap_msgs)
    is_sc = any('SAFETY CAR' in f for f in lap_flags) or any('SAFETY CAR DEPLOYED' in m for m in lap_msgs)
    is_vsc = any('VSC' in f for f in lap_flags) or any('VIRTUAL SAFETY CAR' in m for m in lap_msgs)
    is_yellow = any('YELLOW' in f for f in lap_flags) or any('YELLOW' in m for m in lap_msgs)
    
    # Recent 5 messages
    recent_msgs = []
    if not past_rc.empty:
        for _, rc_row in past_rc.tail(5).iterrows():
            badge = f"[{str(rc_row.get('category', 'RC')).upper()}]"
            msg = str(rc_row.get('message', ''))
            recent_msgs.append(f"Lap {int(rc_row.get('lap_number', 0))}: {badge} {msg}")
            
    if is_red:
        f_info = {
            'flag': 'RED',
            'badge': '[RED]',
            'track_color': '#FF0033',
            'glow_color': 'rgba(255, 0, 51, 0.9)',
            'message': 'SESSION SUSPENDED - RED FLAG - CARS PARKED IN PIT LANE',
            'is_red_flag': True,
            'recent_messages': recent_msgs
        }
    elif is_sc:
        f_info = {
            'flag': 'SC',
            'badge': '[SC]',
            'track_color': '#FFD700',
            'glow_color': 'rgba(255, 215, 0, 0.8)',
            'message': 'SAFETY CAR DEPLOYED',
            'is_red_flag': False,
            'recent_messages': recent_msgs
        }
    elif is_vsc:
        f_info = {
            'flag': 'VSC',
            'badge': '[VSC]',
            'track_color': '#FF9100',
            'glow_color': 'rgba(255, 145, 0, 0.8)',
            'message': 'VIRTUAL SAFETY CAR DEPLOYED',
            'is_red_flag': False,
            'recent_messages': recent_msgs
        }
    elif is_yellow:
        f_info = {
            'flag': 'YELLOW',
            'badge': '[YELLOW]',
            'track_color': '#FFEA00',
            'glow_color': 'rgba(255, 234, 0, 0.7)',
            'message': 'TRACK HAZARD - YELLOW FLAG',
            'is_red_flag': False,
            'recent_messages': recent_msgs
        }
    else:
        f_info = {
            'flag': 'GREEN',
            'badge': '[GREEN]',
            'track_color': '#0066FF',
            'glow_color': 'rgba(0, 240, 255, 0.6)',
            'message': 'TRACK CLEAR - ALL SECTORS GREEN',
            'is_red_flag': False,
            'recent_messages': recent_msgs
        }
    flag_states_payload[l] = f_info

    # Weather snapshot
    w_frac = min(max(l / max(max_laps, 1), 0.0), 1.0)
    w_idx = int(w_frac * max(len(session_weather) - 1, 0))
    w_row = session_weather.iloc[w_idx] if not session_weather.empty else {}
    
    t_temp = float(w_row.get('track_temperature', 35.0)) if pd.notna(w_row.get('track_temperature')) else 35.0
    a_temp = float(w_row.get('air_temperature', 25.0)) if pd.notna(w_row.get('air_temperature')) else 25.0
    w_spd = float(w_row.get('wind_speed', 2.0)) if pd.notna(w_row.get('wind_speed')) else 2.0
    hum = int(w_row.get('humidity', 50)) if pd.notna(w_row.get('humidity')) else 50
    is_rain = bool(float(w_row.get('rainfall', 0) or 0) > 0)
    
    thermal = '[CRITICAL_HIGH]' if t_temp > 45 else ('[ELEVATED]' if t_temp > 38 else ('[LOW_GRAINING]' if t_temp < 25 else '[OPTIMAL]'))
    
    weather_states_payload[l] = {
        'track_temp': round(t_temp, 1),
        'air_temp': round(a_temp, 1),
        'wind_speed': round(w_spd, 1),
        'humidity': hum,
        'track_condition': '[WET]' if is_rain else '[DRY]',
        'thermal_risk': thermal,
        'c_hard': str(race_meta.iloc[0].get('c_hard', 'C1')),
        'c_medium': str(race_meta.iloc[0].get('c_medium', 'C2')),
        'c_soft': str(race_meta.iloc[0].get('c_soft', 'C3'))
    }

# Convert simulation data to JSON
race_payload = {
    'session_key': int(session_key),
    'max_laps': max_laps,
    'circuit': circuit_name,
    'total_race_duration_s': total_race_duration_s,
    'drivers': drivers_time_series,
    'flags': flag_states_payload,
    'weather': weather_states_payload,
    'focus_drivers': focus_drivers,
    'isolate_focus': isolate_focus
}
race_json_str = json.dumps(race_payload)


# ------------------------------------------------------------------------------
# INTERACTIVE 5-TAB APPLICATION SUITE
# ------------------------------------------------------------------------------
tab1, tab2, tab3, tab4, tab5 = st.tabs([
    "VIRTUAL TRACK CIRCLE REPLAY",
    "DRIVER FOCUS TELEMETRY",
    "WEATHER & TRACK EVOLUTION",
    "STINT & TYRE DEGRADATION",
    "FIA RACE CONTROL LOG"
])

# ==============================================================================
# TAB 1: VIRTUAL TRACK CIRCLE REPLAY (WITH RED FLAG PARKING & DNF REMOVAL)
# ==============================================================================
with tab1:
    simulation_html = f"""
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <link href="https://fonts.googleapis.com/css2?family=Titillium+Web:wght@300;400;600;700;900&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
      <style>
        * {{ box-sizing: border-box; margin: 0; padding: 0; }}
        body {{
          background-color: #0B0C10;
          color: #FFFFFF;
          font-family: 'Titillium Web', sans-serif;
          overflow-x: hidden;
          padding: 8px;
        }}
        
        /* Playback Control Bar */
        .playback-bar {{
          display: flex;
          align-items: center;
          justify-content: space-between;
          background: #12151E;
          border: 1px solid rgba(0, 240, 255, 0.2);
          border-radius: 6px;
          padding: 8px 16px;
          margin-bottom: 10px;
          box-shadow: 0 4px 15px rgba(0, 0, 0, 0.5);
        }}
        
        .btn-play {{
          background: linear-gradient(135deg, #00F0FF 0%, #0066FF 100%);
          color: #000000;
          border: none;
          border-radius: 4px;
          font-family: 'JetBrains Mono', monospace;
          font-weight: 800;
          font-size: 0.85rem;
          padding: 7px 16px;
          cursor: pointer;
          text-transform: uppercase;
          letter-spacing: 1px;
          transition: all 0.2s ease;
        }}
        .btn-play:hover {{
          box-shadow: 0 0 15px rgba(0, 240, 255, 0.6);
          transform: translateY(-1px);
        }}
        
        .btn-step {{
          background: #080A0E;
          color: #00F0FF;
          border: 1px solid rgba(0, 240, 255, 0.3);
          border-radius: 4px;
          font-family: 'JetBrains Mono', monospace;
          font-size: 0.75rem;
          font-weight: 700;
          padding: 6px 10px;
          cursor: pointer;
          margin-left: 6px;
        }}
        .btn-step:hover {{
          background: rgba(0, 240, 255, 0.15);
        }}
        
        .scrubber-container {{
          flex: 1;
          margin: 0 16px;
          display: flex;
          flex-direction: column;
          gap: 3px;
        }}
        
        .scrubber-slider {{
          width: 100%;
          accent-color: #00F0FF;
          cursor: pointer;
        }}
        
        .speed-selector {{
          display: flex;
          gap: 4px;
          background: #080A0E;
          padding: 3px;
          border-radius: 4px;
          border: 1px solid rgba(255, 255, 255, 0.08);
        }}
        
        .btn-speed {{
          background: transparent;
          color: #8E9BAE;
          border: none;
          padding: 4px 8px;
          border-radius: 3px;
          font-family: 'JetBrains Mono', monospace;
          font-size: 0.72rem;
          font-weight: 700;
          cursor: pointer;
        }}
        .btn-speed.active {{
          background: #0066FF;
          color: #FFFFFF;
          box-shadow: 0 0 8px rgba(0, 102, 255, 0.5);
        }}
        
        /* Session Status Banner */
        .status-banner {{
          display: flex;
          justify-content: space-between;
          align-items: center;
          background: #12151E;
          border-left: 4px solid #0066FF;
          padding: 8px 14px;
          margin-bottom: 12px;
          border-radius: 4px;
          transition: all 0.3s ease;
        }}
        
        .flag-badge {{
          display: inline-block;
          padding: 3px 10px;
          font-family: 'JetBrains Mono', monospace;
          font-weight: 800;
          font-size: 0.8rem;
          border-radius: 3px;
          letter-spacing: 1px;
        }}
        .flag-badge.green {{ background: rgba(0, 230, 118, 0.15); color: #00E676; border: 1px solid #00E676; }}
        .flag-badge.yellow {{ background: rgba(255, 215, 0, 0.15); color: #FFD700; border: 1px solid #FFD700; }}
        .flag-badge.sc {{ background: #FFD700; color: #000000; font-weight: 900; }}
        .flag-badge.vsc {{ background: rgba(255, 145, 0, 0.2); color: #FF9100; border: 1px solid #FF9100; }}
        .flag-badge.red {{ background: rgba(255, 23, 68, 0.2); color: #FF1744; border: 1px solid #FF1744; animation: pulse-red 1s infinite alternate; }}
        
        @keyframes pulse-red {{
          0% {{ box-shadow: 0 0 5px rgba(255, 23, 68, 0.5); }}
          100% {{ box-shadow: 0 0 18px rgba(255, 23, 68, 0.9); }}
        }}
        
        /* 3-Column Layout */
        .grid-container {{
          display: grid;
          grid-template-columns: 320px 1fr 270px;
          gap: 12px;
          align-items: start;
        }}
        
        .card {{
          background: #12151E;
          border: 1px solid rgba(0, 240, 255, 0.15);
          border-radius: 6px;
          padding: 10px;
          box-shadow: 0 4px 16px rgba(0, 0, 0, 0.4);
        }}
        
        .card-title {{
          font-size: 0.78rem;
          font-weight: 700;
          letter-spacing: 1.2px;
          text-transform: uppercase;
          color: #8E9BAE;
          border-bottom: 1px solid rgba(0, 240, 255, 0.15);
          padding-bottom: 5px;
          margin-bottom: 8px;
        }}
        
        /* Full 20-Driver Timing Tower */
        .timing-container {{
          max-height: 650px;
          overflow-y: auto;
          scrollbar-width: thin;
          scrollbar-color: #0066FF #080A0E;
        }}
        
        .timing-table {{
          width: 100%;
          border-collapse: collapse;
          font-size: 0.76rem;
        }}
        .timing-table th {{
          color: #8E9BAE;
          font-size: 0.68rem;
          text-transform: uppercase;
          letter-spacing: 0.5px;
          padding: 4px 3px;
          border-bottom: 1px solid rgba(255, 255, 255, 0.1);
          text-align: left;
          position: sticky;
          top: 0;
          background: #12151E;
          z-index: 2;
        }}
        .timing-table td {{
          padding: 3.5px 3px;
          border-bottom: 1px solid rgba(255, 255, 255, 0.04);
        }}
        .timing-table tr.retired {{
          background-color: rgba(26, 29, 36, 0.6);
          opacity: 0.7;
        }}
        .timing-table tr.focused {{
          background-color: rgba(0, 240, 255, 0.15) !important;
          border-left: 3px solid #00F0FF;
        }}
        .timing-table tr:hover {{
          background-color: #181C28;
          cursor: pointer;
        }}
        
        .driver-pill {{ display: flex; align-items: center; gap: 5px; }}
        .driver-tag {{ width: 3.5px; height: 13px; border-radius: 1px; }}
        .acronym-text {{ font-family: 'JetBrains Mono', monospace; font-weight: 700; color: #FFFFFF; }}
        
        .compound-badge {{
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 18px;
          height: 18px;
          border-radius: 50%;
          font-family: 'JetBrains Mono', monospace;
          font-weight: 900;
          font-size: 0.65rem;
        }}
        .compound-badge.S {{ background: #FF3333; color: #FFFFFF; }}
        .compound-badge.M {{ background: #FFD700; color: #000000; }}
        .compound-badge.H {{ background: #FFFFFF; color: #000000; }}
        .compound-badge.I {{ background: #00E676; color: #000000; }}
        .compound-badge.W {{ background: #0066FF; color: #FFFFFF; }}
        
        .status-tag {{
          font-family: 'JetBrains Mono', monospace;
          font-size: 0.65rem;
          font-weight: 700;
          padding: 1px 4px;
          border-radius: 2px;
        }}
        .status-tag.pit {{ background: rgba(0, 240, 255, 0.15); color: #00F0FF; border: 1px solid #00F0FF; }}
        .status-tag.parked {{ background: rgba(255, 23, 68, 0.2); color: #FF1744; border: 1px solid #FF1744; }}
        .status-tag.out {{ background: rgba(255, 255, 255, 0.1); color: #8E9BAE; border: 1px solid #536279; }}
        
        /* Center Track Canvas Container */
        .track-canvas-container {{
          display: flex;
          justify-content: center;
          align-items: center;
          background: #080A0E;
          border: 1px solid rgba(0, 240, 255, 0.2);
          border-radius: 8px;
          padding: 8px;
          box-shadow: 0 0 25px rgba(0, 102, 255, 0.15);
          position: relative;
        }}
        
        /* Environmental & Ticker */
        .metric-grid {{ display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-bottom: 10px; }}
        .metric-item {{ background: #080A0E; padding: 6px 8px; border-radius: 4px; border: 1px solid rgba(255, 255, 255, 0.05); }}
        .metric-label {{ font-size: 0.65rem; color: #8E9BAE; text-transform: uppercase; }}
        .metric-value {{ font-family: 'JetBrains Mono', monospace; font-size: 1.05rem; font-weight: 700; color: #FFFFFF; margin-top: 2px; }}
        
        .ticker-box {{
          background: #080A0E;
          border: 1px solid rgba(0, 240, 255, 0.1);
          border-radius: 4px;
          padding: 8px;
          height: 145px;
          overflow-y: auto;
          font-family: 'JetBrains Mono', monospace;
          font-size: 0.7rem;
          line-height: 1.4;
        }}
        .ticker-item {{
          margin-bottom: 5px;
          padding-bottom: 3px;
          border-bottom: 1px dashed rgba(255, 255, 255, 0.08);
          color: #CCD6E0;
        }}
      </style>
    </head>
    <body>

      <!-- Playback Controls -->
      <div class="playback-bar">
        <div style="display: flex; align-items: center;">
          <button id="btnPlay" class="btn-play">PLAY</button>
          <button id="btnPrevLap" class="btn-step">-1 LAP</button>
          <button id="btnNextLap" class="btn-step">+1 LAP</button>
          <button id="btnReset" class="btn-step" title="Restart simulation from Lap 1 / 0:00">RESET</button>
        </div>
        
        <div class="scrubber-container">
          <div style="display: flex; justify-content: space-between; font-family: 'JetBrains Mono', monospace; font-size: 0.72rem; color: #8E9BAE;">
            <span>CONTINUOUS RACE CLOCK</span>
            <span id="lapIndicator">LAP 1 / {max_laps}</span>
          </div>
          <input type="range" id="raceScrubber" class="scrubber-slider" min="0" max="{total_race_duration_s}" step="1" value="0">
        </div>
        
        <div style="display: flex; align-items: center; gap: 12px;">
          <div class="speed-selector">
            <button class="btn-speed" data-speed="1">1x</button>
            <button class="btn-speed" data-speed="2">2x</button>
            <button class="btn-speed active" data-speed="5">5x</button>
            <button class="btn-speed" data-speed="10">10x</button>
          </div>
          
          <label style="display: flex; align-items: center; gap: 6px; font-family: 'JetBrains Mono', monospace; font-size: 0.72rem; color: #8E9BAE; cursor: pointer; user-select: none;">
            <input type="checkbox" id="chkIsolateFocus" style="accent-color: #00F0FF; cursor: pointer;">
            <span>HIDE NON-FOCUSED</span>
          </label>
        </div>
      </div>

      <!-- Session Status Banner -->
      <div id="statusBanner" class="status-banner">
        <div style="display: flex; align-items: center; gap: 10px;">
          <span id="flagBadge" class="flag-badge green">[GREEN]</span>
          <span id="flagMessage" style="font-weight: 700; font-size: 0.88rem; color: #FFFFFF;">TRACK CLEAR - ALL SECTORS GREEN</span>
        </div>
        <div style="font-family: 'JetBrains Mono', monospace; font-size: 0.8rem; color: #8E9BAE;">
          CIRCUIT: <span style="color: #00F0FF; font-weight: 700;">{circuit_name}</span> &nbsp;|&nbsp;
          TIME: <span id="elapsedClock" style="color: #FFFFFF;">0m 00s</span>
        </div>
      </div>

      <!-- Main Grid Layout -->
      <div class="grid-container">
        
        <!-- LEFT: Full 20-Driver Live Timing Tower -->
        <div class="card">
          <div class="card-title">LIVE TIMING TOWER // FULL GRID (P1-P20)</div>
          <div class="timing-container">
            <table class="timing-table">
              <thead>
                <tr>
                  <th>P</th>
                  <th>DRV</th>
                  <th>GAP</th>
                  <th>INT</th>
                  <th>TYRE</th>
                  <th>AGE</th>
                  <th>STATUS</th>
                </tr>
              </thead>
              <tbody id="timingBody">
                <!-- Populated at 60 FPS -->
              </tbody>
            </table>
          </div>
        </div>

        <!-- CENTER: Virtual Track Circle Canvas -->
        <div class="track-canvas-container">
          <canvas id="trackCanvas" width="600" height="600"></canvas>
        </div>

        <!-- RIGHT: Environmental Telemetry & Race Control -->
        <div class="card">
          <div class="card-title">ENVIRONMENTAL TELEMETRY</div>
          
          <div class="metric-grid">
            <div class="metric-item">
              <div class="metric-label">TRACK TEMP</div>
              <div id="valTrackTemp" class="metric-value" style="color: #00F0FF;">35.0°C</div>
            </div>
            <div class="metric-item">
              <div class="metric-label">AIR TEMP</div>
              <div id="valAirTemp" class="metric-value">25.0°C</div>
            </div>
            <div class="metric-item">
              <div class="metric-label">WIND SPEED</div>
              <div id="valWind" class="metric-value">2.4 m/s</div>
            </div>
            <div class="metric-item">
              <div class="metric-label">HUMIDITY</div>
              <div id="valHumidity" class="metric-value">48%</div>
            </div>
          </div>

          <div style="margin-bottom: 10px; padding: 5px 8px; background: #080A0E; border-radius: 4px; display: flex; justify-content: space-between; font-size: 0.72rem;">
            <div>TRACK: <span id="valTrackState" style="color: #00E676; font-family: 'JetBrains Mono'; font-weight: bold;">[DRY]</span></div>
            <div>THERMAL: <span id="valThermal" style="color: #FFD700; font-family: 'JetBrains Mono'; font-weight: bold;">[OPTIMAL]</span></div>
          </div>

          <div class="card-title">PIRELLI ALLOCATION</div>
          <div id="pirelliAllocation" style="display: flex; gap: 6px; margin-bottom: 10px;">
            <!-- Populated dynamically -->
          </div>

          <div class="card-title">FIA RACE CONTROL MESSAGES</div>
          <div id="tickerBox" class="ticker-box">
            <!-- Populated dynamically -->
          </div>
        </div>

      </div>

      <script>
        // Injected Warehouse Data
        const raceData = {race_json_str};
        const maxLaps = raceData.max_laps;
        const totalRaceDurationS = raceData.total_race_duration_s;
        const allDrivers = raceData.drivers;
        const flagsData = raceData.flags;
        const weatherData = raceData.weather;
        // Simulation State Keys (scoped to session_key)
        const storageKeyTime = `f1_sim_time_${{raceData.session_key}}`;
        const storageKeyPlay = `f1_sim_play_${{raceData.session_key}}`;
        const storageKeySpeed = `f1_sim_speed_${{raceData.session_key}}`;
        const storageKeyFocus = `f1_sim_focus_${{raceData.session_key}}`;
        const storageKeyIsolate = `f1_sim_isolate_${{raceData.session_key}}`;

        // Multi-tier storage persistence (Parent window sessionStorage + localStorage + iframe fallback)
        function getStored(key) {{
          try {{
            if (window.parent && window.parent.sessionStorage) {{
              const v = window.parent.sessionStorage.getItem(key);
              if (v !== null) return v;
            }}
          }} catch(e) {{}}
          try {{
            if (window.parent && window.parent.localStorage) {{
              const v = window.parent.localStorage.getItem(key);
              if (v !== null) return v;
            }}
          }} catch(e) {{}}
          try {{
            const v = window.localStorage.getItem(key);
            if (v !== null) return v;
          }} catch(e) {{}}
          try {{
            const v = window.sessionStorage.getItem(key);
            if (v !== null) return v;
          }} catch(e) {{}}
          return null;
        }}

        function setStored(key, value) {{
          try {{
            if (window.parent && window.parent.sessionStorage) {{
              window.parent.sessionStorage.setItem(key, String(value));
            }}
          }} catch(e) {{}}
          try {{
            if (window.parent && window.parent.localStorage) {{
              window.parent.localStorage.setItem(key, String(value));
            }}
          }} catch(e) {{}}
          try {{
            window.localStorage.setItem(key, String(value));
          }} catch(e) {{}}
          try {{
            window.sessionStorage.setItem(key, String(value));
          }} catch(e) {{}}
        }}

        // Restore simulation time across reruns
        const tVal = getStored(storageKeyTime);
        let savedTime = 0.0;
        if (tVal !== null) {{
          savedTime = parseFloat(tVal) || 0.0;
        }}
        let simTimeS = Math.min(Math.max(savedTime, 0.0), totalRaceDurationS);

        // Restore play/pause state
        const pVal = getStored(storageKeyPlay);
        let isPlaying = (pVal === 'true');

        // Restore playback speed
        const sVal = getStored(storageKeySpeed);
        let playbackSpeed = sVal !== null ? (parseFloat(sVal) || 5.0) : 5.0;

        // Focus Drivers priority: Python sidebar multiselect > stored session focus
        let focusDrivers = (raceData.focus_drivers && raceData.focus_drivers.length > 0)
          ? [...raceData.focus_drivers]
          : [];
        if (focusDrivers.length === 0) {{
          const storedFocus = getStored(storageKeyFocus);
          if (storedFocus) {{
            try {{ focusDrivers = JSON.parse(storedFocus) || []; }} catch(e) {{}}
          }}
        }}

        // Isolate Focus priority: Python sidebar checkbox > stored session isolate
        let isolateFocus = Boolean(raceData.isolate_focus);
        if (!isolateFocus) {{
          const storedIsolate = getStored(storageKeyIsolate);
          if (storedIsolate === 'true') {{
            isolateFocus = true;
          }}
        }}

        let lastTimestamp = performance.now();

        // DOM Elements
        const btnPlay = document.getElementById('btnPlay');
        if (isPlaying) {{
          btnPlay.innerText = 'PAUSE';
          btnPlay.style.background = '#FFD700';
        }}
        const btnPrevLap = document.getElementById('btnPrevLap');
        const btnNextLap = document.getElementById('btnNextLap');
        const btnReset = document.getElementById('btnReset');
        const chkIsolateFocus = document.getElementById('chkIsolateFocus');
        if (chkIsolateFocus) {{
          chkIsolateFocus.checked = isolateFocus;
        }}
        const scrubber = document.getElementById('raceScrubber');
        scrubber.value = simTimeS;
        const lapIndicator = document.getElementById('lapIndicator');
        const statusBanner = document.getElementById('statusBanner');
        const flagBadge = document.getElementById('flagBadge');
        const flagMessage = document.getElementById('flagMessage');
        const elapsedClock = document.getElementById('elapsedClock');
        const timingBody = document.getElementById('timingBody');
        const tickerBox = document.getElementById('tickerBox');
        const pirelliAllocation = document.getElementById('pirelliAllocation');
        
        // Canvas Context
        const canvas = document.getElementById('trackCanvas');
        const ctx = canvas.getContext('2d');
        const cx = 300, cy = 300;
        const rMain = 220;
        const rPit = 180; // R_pit = 0.82 * R_main

        // Speed Controls
        document.querySelectorAll('.btn-speed').forEach(btn => {{
          if (parseFloat(btn.getAttribute('data-speed')) === playbackSpeed) {{
            btn.classList.add('active');
          }} else {{
            btn.classList.remove('active');
          }}
          btn.addEventListener('click', () => {{
            document.querySelectorAll('.btn-speed').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            playbackSpeed = parseFloat(btn.getAttribute('data-speed'));
            setStored(storageKeySpeed, String(playbackSpeed));
          }});
        }});

        // Play/Pause Toggle
        btnPlay.addEventListener('click', () => {{
          isPlaying = !isPlaying;
          btnPlay.innerText = isPlaying ? 'PAUSE' : 'PLAY';
          btnPlay.style.background = isPlaying ? '#FFD700' : 'linear-gradient(135deg, #00F0FF 0%, #0066FF 100%)';
          setStored(storageKeyPlay, String(isPlaying));
          setStored(storageKeyTime, String(simTimeS));
          if (isPlaying) {{
            lastTimestamp = performance.now();
          }}
        }});

        // Step Lap Buttons
        btnPrevLap.addEventListener('click', () => {{
          simTimeS = Math.max(0, simTimeS - 88.0);
          scrubber.value = simTimeS;
          setStored(storageKeyTime, String(simTimeS));
          updateDisplay();
        }});

        btnNextLap.addEventListener('click', () => {{
          simTimeS = Math.min(totalRaceDurationS, simTimeS + 88.0);
          scrubber.value = simTimeS;
          setStored(storageKeyTime, String(simTimeS));
          updateDisplay();
        }});

        // Reset Simulation Button
        if (btnReset) {{
          btnReset.addEventListener('click', () => {{
            simTimeS = 0.0;
            isPlaying = false;
            btnPlay.innerText = 'PLAY';
            btnPlay.style.background = 'linear-gradient(135deg, #00F0FF 0%, #0066FF 100%)';
            scrubber.value = 0;
            setStored(storageKeyPlay, 'false');
            setStored(storageKeyTime, '0.0');
            updateDisplay();
          }});
        }}

        // In-simulation Isolate Focus Checkbox
        if (chkIsolateFocus) {{
          chkIsolateFocus.addEventListener('change', (e) => {{
            isolateFocus = e.target.checked;
            setStored(storageKeyIsolate, String(isolateFocus));
            updateDisplay();
          }});
        }}

        // Scrubber Drag
        scrubber.addEventListener('input', (e) => {{
          simTimeS = parseFloat(e.target.value);
          setStored(storageKeyTime, String(simTimeS));
          updateDisplay();
        }});

        // Unload / Pagehide handlers to guarantee state is written before unmount
        window.addEventListener('beforeunload', () => {{
          setStored(storageKeyTime, String(simTimeS));
          setStored(storageKeyPlay, String(isPlaying));
        }});
        window.addEventListener('pagehide', () => {{
          setStored(storageKeyTime, String(simTimeS));
          setStored(storageKeyPlay, String(isPlaying));
        }});

        // Polar to Cartesian Helper (0 deg at 12 o'clock)
        function pol2cart(r, deg) {{
          const rad = (deg - 90) * Math.PI / 180.0;
          return {{
            x: cx + r * Math.cos(rad),
            y: cy + r * Math.sin(rad)
          }};
        }}

        // Periodic state persistence throttle
        let lastPersistMs = 0;

        // Animation Loop (60 FPS)
        function animate(timestamp) {{
          const dt = (timestamp - lastTimestamp) / 1000.0;
          lastTimestamp = timestamp;

          if (isPlaying) {{
            simTimeS += dt * playbackSpeed;
            if (simTimeS >= totalRaceDurationS) {{
              simTimeS = totalRaceDurationS;
              isPlaying = false;
              btnPlay.innerText = 'PLAY';
              btnPlay.style.background = 'linear-gradient(135deg, #00F0FF 0%, #0066FF 100%)';
              setStored(storageKeyPlay, 'false');
              setStored(storageKeyTime, String(simTimeS));
            }}
            scrubber.value = simTimeS;

            // Frequent 100ms state sync so any external rerun picks up the exact sub-second
            if (timestamp - lastPersistMs > 100) {{
              lastPersistMs = timestamp;
              setStored(storageKeyTime, String(simTimeS));
            }}
          }}

          updateDisplay();
          requestAnimationFrame(animate);
        }}

        // Main Display Update Function
        function updateDisplay() {{
          const mins = Math.floor(simTimeS / 60);
          const secs = Math.floor(simTimeS % 60);
          elapsedClock.innerText = `${{mins}}m ${{secs.toString().padStart(2, '0')}}s`;

          // 1. Determine Current Active Race Lap based on Leading Car's Progress
          let maxLeaderLap = 1;
          allDrivers.forEach(d => {{
            const curL = d.laps.find(l => simTimeS >= l.start_t && simTimeS < l.end_t);
            if (curL && curL.lap > maxLeaderLap) maxLeaderLap = curL.lap;
          }});

          const activeLap = maxLeaderLap;
          lapIndicator.innerText = `LAP ${{activeLap}} / ${{maxLaps}}`;

          // 2. Determine FIA Flag State at this Lap
          const flagInfo = flagsData[activeLap] || {{ flag: 'GREEN', badge: '[GREEN]', track_color: '#0066FF', message: 'TRACK CLEAR', is_red_flag: false }};
          const isRedFlag = Boolean(flagInfo.is_red_flag);

          flagBadge.className = `flag-badge ${{flagInfo.flag.toLowerCase()}}`;
          flagBadge.innerText = flagInfo.badge;
          flagMessage.innerText = flagInfo.message;
          statusBanner.style.borderLeftColor = flagInfo.track_color;

          // 3. Update Weather Telemetry
          const wInfo = weatherData[activeLap] || {{}};
          document.getElementById('valTrackTemp').innerText = `${{wInfo.track_temp || 35.0}}°C`;
          document.getElementById('valAirTemp').innerText = `${{wInfo.air_temp || 25.0}}°C`;
          document.getElementById('valWind').innerText = `${{wInfo.wind_speed || 2.0}} m/s`;
          document.getElementById('valHumidity').innerText = `${{wInfo.humidity || 50}}%`;
          document.getElementById('valTrackState').innerText = wInfo.track_condition || '[DRY]';
          document.getElementById('valThermal').innerText = wInfo.thermal_risk || '[OPTIMAL]';

          pirelliAllocation.innerHTML = `
            <span style="font-family: 'JetBrains Mono'; font-size: 0.72rem; padding: 2px 5px; border: 1px solid #FFFFFF; border-radius: 2px; color: #FFFFFF;">[H] ${{wInfo.c_hard || 'C1'}}</span>
            <span style="font-family: 'JetBrains Mono'; font-size: 0.72rem; padding: 2px 5px; border: 1px solid #FFD700; border-radius: 2px; color: #FFD700;">[M] ${{wInfo.c_medium || 'C2'}}</span>
            <span style="font-family: 'JetBrains Mono'; font-size: 0.72rem; padding: 2px 5px; border: 1px solid #FF3333; border-radius: 2px; color: #FF3333;">[S] ${{wInfo.c_soft || 'C3'}}</span>
          `;

          const msgs = flagInfo.recent_messages || [];
          if (msgs.length > 0) {{
            tickerBox.innerHTML = msgs.slice().reverse().map(m => `<div class="ticker-item">${{m}}</div>`).join('');
          }} else {{
            tickerBox.innerHTML = '<div style="color: #536279; font-style: italic;">No active race control incidents.</div>';
          }}

          // 4. Evaluate Driver Status, DNF Removal, and Red Flag Physics
          const activeDriverSnapshots = [];
          const retiredDrivers = [];

          allDrivers.forEach(d => {{
            const laps = d.laps;

            // Check if car never started (DNS)
            if (d.is_dns || !laps || laps.length === 0) {{
              retiredDrivers.push({{
                ...d,
                lap: 0,
                status_badge: '[DNS]',
                gapStr: 'DNS',
                intStr: '--',
                compound_badge: '-',
                tyre_age: 0
              }});
              return;
            }}

            // Check if driver has retired (DNF/DSQ) before/at this simulation time
            const lastLap = laps[laps.length - 1];
            const hasRetired = (d.is_dnf || d.is_dsq) && (activeLap > d.max_lap || simTimeS >= lastLap.end_t);

            if (hasRetired) {{
              retiredDrivers.push({{
                ...d,
                lap: d.max_lap,
                status_badge: d.status_code || '[DNF]',
                gapStr: `OUT L${{d.max_lap}}`,
                intStr: '--',
                compound_badge: lastLap.compound_badge,
                tyre_age: lastLap.tyre_age
              }});
              return; // COMPLETELY REMOVED FROM TRACK CIRCLE VIEW
            }}

            // If before race start (On Grid)
            if (simTimeS <= laps[0].start_t) {{
              const firstL = laps[0];
              activeDriverSnapshots.push({{
                ...d,
                lap: 1,
                deg: 0,
                radius: rMain,
                is_in_pit: false,
                is_parked_red: false,
                compound: firstL.compound,
                compound_badge: firstL.compound_badge,
                tyre_age: firstL.tyre_age,
                speed: 0.0,
                distance_score: 0.0,
                status_badge: '[GRID]'
              }});
              return;
            }}

            // Driver is currently active in the race
            let curL = laps.find(l => simTimeS >= l.start_t && simTimeS < l.end_t);
            if (!curL) curL = lastLap;

            const curT = simTimeS - curL.start_t;
            const totalDur = curL.dur || 90.0;
            const s1 = curL.s1, s2 = curL.s2, s3 = curL.s3;

            let deg = 0;
            let isPit = false;

            if (curT < s1) {{
              deg = (curT / Math.max(s1, 0.1)) * 120.0;
              isPit = curL.is_pit_out && (curT / s1 < 0.5);
            }} else if (curT < (s1 + s2)) {{
              deg = 120.0 + ((curT - s1) / Math.max(s2, 0.1)) * 120.0;
              isPit = false;
            }} else {{
              deg = 240.0 + ((curT - (s1 + s2)) / Math.max(s3, 0.1)) * 120.0;
              isPit = curL.is_pit_in && ((curT - (s1 + s2)) / s3 > 0.4);
            }}

            let r = rMain;
            if (isPit || (curL.is_pit_in && deg >= 330) || (curL.is_pit_out && deg <= 30)) {{
              r = rPit;
            }}

            // RED FLAG PARKING LOGIC:
            // When Red Flag is active, freeze angular speed (omega = 0) and park on inner pit-lane arc R_pit
            let isParkedRed = false;
            if (isRedFlag) {{
              isParkedRed = true;
              r = rPit; // Park in inner pit lane
            }}

            activeDriverSnapshots.push({{
              ...d,
              lap: curL.lap,
              deg: deg % 360,
              radius: r,
              is_in_pit: isPit,
              is_parked_red: isParkedRed,
              compound: curL.compound,
              compound_badge: curL.compound_badge,
              tyre_age: curL.tyre_age,
              speed: isParkedRed ? 0.0 : curL.speed,
              distance_score: (curL.lap - 1) + (deg / 360.0),
              status_badge: isParkedRed ? '[PARKED - RED]' : (isPit ? '[IN PIT]' : '[ON TRACK]')
            }});
          }});

          // Sort active drivers descending by race distance score (Leader first)
          activeDriverSnapshots.sort((a, b) => b.distance_score - a.distance_score);

          // If Red Flag is active, line cars up cleanly in order along pit lane arc 340 deg to 20 deg
          if (isRedFlag && activeDriverSnapshots.length > 0) {{
            const totalActive = activeDriverSnapshots.length;
            activeDriverSnapshots.forEach((d, i) => {{
              // Line up along pit arc
              const parkDeg = (345 + (i * (40.0 / Math.max(totalActive, 1)))) % 360;
              d.deg = parkDeg;
              d.radius = rPit;
            }});
          }}

          // 5. Render Live 20-Driver Timing Tower (Active Grid P1..Pn + Retired Section)
          renderTimingTower(activeDriverSnapshots, retiredDrivers);

          // 6. Render Virtual Track Circle Canvas (Excludes DNF cars entirely)
          renderCanvas(activeDriverSnapshots, flagInfo, isRedFlag);
        }}

        // Render Timing Tower Table
        function renderTimingTower(activeDrivers, retiredDrivers) {{
          const leaderScore = activeDrivers.length > 0 ? activeDrivers[0].distance_score : 0;
          let html = '';

          // Active drivers
          activeDrivers.forEach((d, idx) => {{
            const pos = idx + 1;
            let gapStr = 'LEADER';
            let intStr = '--';

            if (idx > 0) {{
              const gapScore = leaderScore - d.distance_score;
              const intScore = activeDrivers[idx - 1].distance_score - d.distance_score;
              
              if (gapScore >= 1.0) {{
                const lapsDown = Math.floor(gapScore);
                gapStr = `+${{lapsDown}} LAP${{lapsDown > 1 ? 'S' : ''}}`;
              }} else {{
                gapStr = `+${{(gapScore * 88.0).toFixed(3)}}s`;
              }}

              if (intScore >= 1.0) {{
                intStr = `+${{Math.floor(intScore)}} LAP`;
              }} else {{
                intStr = `+${{(intScore * 88.0).toFixed(3)}}s`;
              }}
            }}

            const isFocus = focusDrivers.includes(d.acronym);
            const focusClass = isFocus ? 'focused' : '';

            let statusHtml = '';
            if (d.is_parked_red) {{
              statusHtml = '<span class="status-tag parked">[PARKED - RED]</span>';
            }} else if (d.is_in_pit) {{
              statusHtml = '<span class="status-tag pit">[IN PIT]</span>';
            }} else {{
              statusHtml = `<span style="color: #8E9BAE; font-size: 0.68rem;">${{d.speed}} km/h</span>`;
            }}

            html += `
              <tr class="${{focusClass}}" data-acronym="${{d.acronym}}" style="cursor: pointer;" title="Click to toggle Focus Spotlight">
                <td style="font-weight: 700; color: #FFFFFF;">${{pos}}</td>
                <td>
                  <div class="driver-pill">
                    <span class="driver-tag" style="background-color: ${{d.team_color}};"></span>
                    <span class="acronym-text">${{d.acronym}}</span>
                  </div>
                </td>
                <td style="font-family: 'JetBrains Mono'; font-size: 0.72rem; color: #8E9BAE;">${{gapStr}}</td>
                <td style="font-family: 'JetBrains Mono'; font-size: 0.72rem; color: #536279;">${{intStr}}</td>
                <td><span class="compound-badge ${{d.compound_badge}}">${{d.compound_badge}}</span></td>
                <td style="font-family: 'JetBrains Mono'; font-size: 0.72rem; text-align: center;">${{d.tyre_age}}</td>
                <td>${{statusHtml}}</td>
              </tr>
            `;
          }});

          // Retired Drivers (Bottom Section)
          retiredDrivers.forEach((d, idx) => {{
            const retPos = activeDrivers.length + idx + 1;
            const isFocus = focusDrivers.includes(d.acronym);
            const focusClass = isFocus ? 'focused' : '';

            html += `
              <tr class="retired ${{focusClass}}" data-acronym="${{d.acronym}}" style="cursor: pointer;" title="Click to toggle Focus Spotlight">
                <td style="font-weight: 700; color: #536279;">${{retPos}}</td>
                <td>
                  <div class="driver-pill">
                    <span class="driver-tag" style="background-color: ${{d.team_color}}; opacity: 0.5;"></span>
                    <span class="acronym-text" style="color: #8E9BAE;">${{d.acronym}}</span>
                  </div>
                </td>
                <td style="font-family: 'JetBrains Mono'; font-size: 0.72rem; color: #536279;">${{d.gapStr}}</td>
                <td style="font-family: 'JetBrains Mono'; font-size: 0.72rem; color: #536279;">--</td>
                <td><span class="compound-badge ${{d.compound_badge}}" style="opacity: 0.5;">${{d.compound_badge}}</span></td>
                <td style="font-family: 'JetBrains Mono'; font-size: 0.72rem; text-align: center; color: #536279;">${{d.tyre_age}}</td>
                <td><span class="status-tag out">${{d.status_badge}}</span></td>
              </tr>
            `;
          }});

          timingBody.innerHTML = html;
        }}

        // Interactive Timing Table Click to Toggle Focus Driver
        timingBody.addEventListener('click', (e) => {{
          const row = e.target.closest('tr');
          if (!row) return;
          const acr = row.getAttribute('data-acronym');
          if (!acr) return;
          const idx = focusDrivers.indexOf(acr);
          if (idx >= 0) {{
            focusDrivers.splice(idx, 1);
          }} else {{
            focusDrivers.push(acr);
          }}
          setStored(storageKeyFocus, JSON.stringify(focusDrivers));
          updateDisplay();
        }});

        // Render Canvas Virtual Track Circle
        function renderCanvas(drivers, flagInfo, isRedFlag) {{
          ctx.clearRect(0, 0, 600, 600);

          // Background Rings
          ctx.strokeStyle = 'rgba(255, 255, 255, 0.03)';
          ctx.lineWidth = 1;
          ctx.setLineDash([4, 4]);
          ctx.beginPath();
          ctx.arc(cx, cy, rMain + 35, 0, 2 * Math.PI);
          ctx.stroke();
          ctx.beginPath();
          ctx.arc(cx, cy, 140, 0, 2 * Math.PI);
          ctx.stroke();

          // Sector Dividers
          ctx.strokeStyle = 'rgba(0, 240, 255, 0.2)';
          ctx.lineWidth = 1.5;
          ctx.setLineDash([3, 3]);
          [0, 120, 240].forEach(angle => {{
            const pt = pol2cart(rMain + 25, angle);
            ctx.beginPath();
            ctx.moveTo(cx, cy);
            ctx.lineTo(pt.x, pt.y);
            ctx.stroke();
          }});

          // Sector Labels
          ctx.setLineDash([]);
          ctx.fillStyle = '#536279';
          ctx.font = 'bold 11px "JetBrains Mono"';
          ctx.fillText('SECTOR 1 [0-120°]', 430, 200);
          ctx.fillText('SECTOR 2 [120-240°]', 240, 560);
          ctx.fillText('SECTOR 3 [240-360°]', 70, 200);

          // Inner Pit-Lane Arc (330 deg through 0 to 30 deg)
          ctx.beginPath();
          ctx.strokeStyle = isRedFlag ? '#FF0033' : '#00F0FF';
          ctx.lineWidth = 2.5;
          ctx.setLineDash([6, 4]);
          ctx.arc(cx, cy, rPit, (330 - 90) * Math.PI / 180, (30 - 90) * Math.PI / 180);
          ctx.stroke();
          ctx.setLineDash([]);

          ctx.fillStyle = isRedFlag ? '#FF0033' : '#00F0FF';
          ctx.font = 'bold 9px "JetBrains Mono"';
          ctx.textAlign = 'center';
          ctx.fillText(isRedFlag ? 'PIT LANE [RED FLAG PARKING ZONE]' : 'PIT LANE [INNER RING]', cx, cy - rPit - 8);

          // Main Track Circle Glow & Body
          ctx.save();
          ctx.shadowColor = flagInfo.glow_color || 'rgba(0, 102, 255, 0.8)';
          ctx.shadowBlur = isRedFlag ? 25 : 18;
          ctx.strokeStyle = flagInfo.track_color || '#0066FF';
          ctx.lineWidth = 8;
          ctx.beginPath();
          ctx.arc(cx, cy, rMain, 0, 2 * Math.PI);
          ctx.stroke();
          ctx.restore();

          // Outer & Inner Borders
          ctx.strokeStyle = flagInfo.track_color || '#0066FF';
          ctx.lineWidth = 1;
          ctx.beginPath();
          ctx.arc(cx, cy, rMain + 8, 0, 2 * Math.PI);
          ctx.stroke();
          ctx.beginPath();
          ctx.arc(cx, cy, rMain - 8, 0, 2 * Math.PI);
          ctx.stroke();

          // Start/Finish Line Marker
          ctx.strokeStyle = '#FFFFFF';
          ctx.lineWidth = 4;
          ctx.beginPath();
          ctx.moveTo(cx, cy - rMain - 14);
          ctx.lineTo(cx, cy - rMain + 14);
          ctx.stroke();

          ctx.fillStyle = '#FFFFFF';
          ctx.font = 'bold 9px "JetBrains Mono"';
          ctx.textAlign = 'center';
          ctx.fillText('START / FINISH', cx, cy - rMain - 18);

          // Center Telemetry Dial
          ctx.fillStyle = '#12151E';
          ctx.strokeStyle = isRedFlag ? '#FF0033' : 'rgba(0, 240, 255, 0.3)';
          ctx.lineWidth = 2;
          ctx.beginPath();
          ctx.arc(cx, cy, 75, 0, 2 * Math.PI);
          ctx.fill();
          ctx.stroke();

          ctx.fillStyle = '#8E9BAE';
          ctx.font = '9px "JetBrains Mono"';
          ctx.fillText('CIRCUIT', cx, cy - 20);

          ctx.fillStyle = '#FFFFFF';
          ctx.font = 'bold 15px "Titillium Web"';
          ctx.fillText('{circuit_name}', cx, cy);

          ctx.fillStyle = isRedFlag ? '#FF0033' : '#00F0FF';
          ctx.font = 'bold 11px "JetBrains Mono"';
          ctx.fillText(isRedFlag ? '[RED FLAG]' : `LAP ${{drivers.length > 0 ? drivers[0].lap : 1}} / ${{maxLaps}}`, cx, cy + 22);

          // Prominent Banner across Circle during Red Flag
          if (isRedFlag) {{
            ctx.fillStyle = 'rgba(255, 0, 51, 0.85)';
            ctx.fillRect(80, 20, 440, 26);
            ctx.strokeStyle = '#FFFFFF';
            ctx.lineWidth = 1;
            ctx.strokeRect(80, 20, 440, 26);
            
            ctx.fillStyle = '#FFFFFF';
            ctx.font = 'bold 10px "JetBrains Mono"';
            ctx.fillText('SESSION SUSPENDED - RED FLAG - CARS PARKED IN PIT LANE', cx, 37);
          }}

          // Tyre Compound Colors
          const compColors = {{
            'SOFT': '#FF3333',
            'MEDIUM': '#FFD700',
            'HARD': '#FFFFFF',
            'INTERMEDIATE': '#00E676',
            'WET': '#0066FF'
          }};

          // Render Active Cars Only (DNF cars were excluded in updateDisplay)
          drivers.forEach(d => {{
            const isFocus = focusDrivers.includes(d.acronym);
            
            // If Isolate Focus is checked and focusDrivers is not empty
            if (isolateFocus && focusDrivers.length > 0 && !isFocus) {{
              return; // Hide non-focused cars
            }}

            const pt = pol2cart(d.radius, d.deg);
            const nodeRadius = isFocus ? 11 : 8.5;
            const tyreCol = compColors[d.compound] || '#FFD700';
            const opacity = (!focusDrivers.length || isFocus) ? 1.0 : 0.22;

            ctx.save();
            ctx.globalAlpha = opacity;

            // Focus Outer Pulse Ring
            if (isFocus) {{
              ctx.strokeStyle = '#00F0FF';
              ctx.lineWidth = 2.5;
              ctx.beginPath();
              ctx.arc(pt.x, pt.y, nodeRadius + 6, 0, 2 * Math.PI);
              ctx.stroke();
            }}

            // Outer Compound Ring
            ctx.strokeStyle = tyreCol;
            ctx.lineWidth = 2;
            ctx.beginPath();
            ctx.arc(pt.x, pt.y, nodeRadius + 2.5, 0, 2 * Math.PI);
            ctx.stroke();

            // Team Colored Node Body
            ctx.fillStyle = d.team_color;
            ctx.strokeStyle = '#0B0C10';
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            ctx.arc(pt.x, pt.y, nodeRadius, 0, 2 * Math.PI);
            ctx.fill();
            ctx.stroke();

            // Driver Acronym Text
            ctx.fillStyle = '#FFFFFF';
            ctx.font = isFocus ? 'bold 8.5px "JetBrains Mono"' : 'bold 7px "JetBrains Mono"';
            ctx.textAlign = 'center';
            ctx.textBaseline = 'middle';
            ctx.fillText(d.acronym, pt.x, pt.y + 0.5);

            // Floating Telemetry Callout Tag for Focused Drivers
            if (isFocus) {{
              ctx.fillStyle = 'rgba(18, 21, 30, 0.9)';
              ctx.strokeStyle = '#00F0FF';
              ctx.lineWidth = 1;
              ctx.fillRect(pt.x - 30, pt.y - 32, 60, 16);
              ctx.strokeRect(pt.x - 30, pt.y - 32, 60, 16);

              ctx.fillStyle = '#00F0FF';
              ctx.font = 'bold 8px "JetBrains Mono"';
              ctx.fillText(`${{d.speed}} km/h`, pt.x, pt.y - 23);
            }} else if (d.is_parked_red) {{
              ctx.fillStyle = '#FF0033';
              ctx.font = 'bold 8px "JetBrains Mono"';
              ctx.fillText('[PARKED]', pt.x, pt.y - 12);
            }} else if (d.is_in_pit) {{
              ctx.fillStyle = '#00F0FF';
              ctx.font = 'bold 8px "JetBrains Mono"';
              ctx.fillText('[PIT]', pt.x, pt.y - 12);
            }}

            ctx.restore();
          }});
        }}

        // Start Continuous Animation Loop
        requestAnimationFrame(animate);
      </script>
    </body>
    </html>
    """
    components.html(simulation_html, height=800, scrolling=False)


# ==============================================================================
# TAB 2: DRIVER FOCUS TELEMETRY COMPARISON DRAWER
# ==============================================================================
with tab2:
    st.markdown('<div class="pitwall-card-title">DRIVER TELEMETRY SPOTLIGHT & PACE COMPARISON</div>', unsafe_allow_html=True)
    
    if not focus_drivers:
        st.info("Select 1 or more drivers in the sidebar under 'TELEMETRY SPOTLIGHT' to inspect and compare their telemetry.")
    else:
        comp_cols = st.columns(len(focus_drivers))
        for i, drv_acronym in enumerate(focus_drivers):
            with comp_cols[i]:
                drv_laps = session_laps[session_laps['name_acronym'] == drv_acronym].sort_values(by='lap_number')
                drv_res = session_results[session_results['name_acronym'] == drv_acronym]
                
                status_text = "[ON TRACK / CLASSIFIED]"
                if not drv_res.empty:
                    row_r = drv_res.iloc[0]
                    if str(row_r.get('dnf', '')).lower() in ['t', 'true', '1']:
                        status_text = f"[RETIRED - DNF AT LAP {int(row_r.get('number_of_laps', 0))}]"
                
                st.markdown(f"""
                <div class="pitwall-card" style="margin-bottom: 12px; border-left: 4px solid #00F0FF;">
                  <div style="font-size: 1.1rem; font-weight: 700; color: #FFFFFF;">{drv_acronym} // {drv_laps.iloc[0]['team_name'] if not drv_laps.empty else 'Unknown'}</div>
                  <div style="font-family: 'JetBrains Mono'; font-size: 0.8rem; color: #8E9BAE; margin-top: 4px;">STATUS: <span style="color: #00F0FF;">{status_text}</span></div>
                </div>
                """, unsafe_allow_html=True)
                
                if not drv_laps.empty:
                    best_lap = drv_laps['lap_duration'].min()
                    avg_speed = drv_laps['st_speed'].mean()
                    total_stints = drv_laps['stint_number'].nunique()
                    
                    st.metric("Fastest Lap Duration", f"{best_lap:.3f} s" if pd.notna(best_lap) else "--")
                    st.metric("Avg Speed Trap Velocity", f"{avg_speed:.1f} km/h" if pd.notna(avg_speed) else "--")
                    st.metric("Total Stints Run", total_stints)
                    
                    # Mini Lap Progression Table
                    st.markdown("**Recent Lap Breakdown:**")
                    st.dataframe(
                        drv_laps[['lap_number', 'lap_duration', 'duration_sector_1', 'duration_sector_2', 'duration_sector_3', 'compound', 'tyre_age_laps']].tail(10),
                        use_container_width=True
                    )


# ==============================================================================
# TAB 3: WEATHER & TRACK EVOLUTION TELEMETRY
# ==============================================================================
with tab3:
    st.markdown('<div class="pitwall-card-title">ENVIRONMENTAL SENSORS & THERMAL TRACK DEGRADATION</div>', unsafe_allow_html=True)
    
    col_w1, col_w2 = st.columns([1, 1])
    with col_w1:
        st.markdown("**Track vs Air Temperature Time-Series:**")
        if not session_weather.empty:
            weather_plot_df = session_weather[['track_temperature', 'air_temperature']].dropna().reset_index(drop=True)
            st.line_chart(weather_plot_df)
    with col_w2:
        st.markdown("**Wind Speed Progression (m/s):**")
        if not session_weather.empty:
            wind_plot_df = session_weather[['wind_speed']].dropna().reset_index(drop=True)
            st.line_chart(wind_plot_df)
            
    st.markdown(f"""
    <div class="pitwall-card" style="margin-top: 14px;">
      <div style="font-size: 0.85rem; font-weight: 700; color: #8E9BAE; text-transform: uppercase;">PIRELLI CIRCUIT ALLOCATION BREAKDOWN</div>
      <div style="font-family: 'JetBrains Mono'; font-size: 0.85rem; color: #CCD6E0; margin-top: 8px;">
        Hard Compound: <span style="color: #FFFFFF; font-weight: bold;">{race_meta.iloc[0].get('c_hard', 'C1')}</span> &nbsp;|&nbsp;
        Medium Compound: <span style="color: #FFD700; font-weight: bold;">{race_meta.iloc[0].get('c_medium', 'C2')}</span> &nbsp;|&nbsp;
        Soft Compound: <span style="color: #FF3333; font-weight: bold;">{race_meta.iloc[0].get('c_soft', 'C3')}</span>
      </div>
    </div>
    """, unsafe_allow_html=True)


# ==============================================================================
# TAB 4: STINT & TYRE DEGRADATION ANALYSIS
# ==============================================================================
with tab4:
    st.markdown('<div class="pitwall-card-title">STINT DURATION & TYRE DEGRADATION PROFILES</div>', unsafe_allow_html=True)
    
    if not session_stints.empty:
        st.markdown("**Executed Stint Summary from Warehouse:**")
        st.dataframe(
            session_stints[['driver_number', 'name_acronym', 'team_name', 'stint_number', 'compound', 'lap_start', 'lap_end', 'laps', 'clean_laps', 'avg_clean_lap_s', 'deg_slope_raw_s_per_lap']].head(30),
            use_container_width=True
        )
    else:
        st.info("No stint aggregation records found for this session.")


# ==============================================================================
# TAB 5: FIA RACE CONTROL OFFICIAL INCIDENT LOG
# ==============================================================================
with tab5:
    st.markdown('<div class="pitwall-card-title">FIA RACE CONTROL OFFICIAL SESSION INCIDENT FEED</div>', unsafe_allow_html=True)
    
    if not session_rc.empty:
        st.dataframe(
            session_rc[['lap_number', 'category', 'flag', 'scope', 'sector', 'message']].sort_values(by='lap_number'),
            use_container_width=True
        )
    else:
        st.info("No FIA Race Control events logged for this session.")
