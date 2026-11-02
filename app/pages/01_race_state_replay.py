"""
Module: 01_race_state_replay.py
Team Member: Moaz (UI Architecture & Dynamic Playback Integration)
             Mohamed (Kinematics & Lap Progress Math)
             Yousef (Pit Lane Inner-Ring & Flag State Machine)
             Mahmud (Weather & Track Telemetry Sync)
Phase: Phase 3 - Race State Simulation & Virtual Track Circle
Objective: High-performance interactive Formula 1 simulation with:
           - Live real-time playback (Play/Pause, Speed 1x-10x, Lap Scrubber).
           - 60 FPS client-side Canvas/SVG simulation showing drivers smoothly moving around the Virtual Track Circle.
           - Zero emojis (strict text badges [S], [M], [H], [I], [W], [PIT], [GREEN], [SC], [VSC], [RED]).
           - Matte Black (#0B0C10) & Electric Pit-Wall Blue (#00F0FF) theme.
"""

import math
import os
import json
import pandas as pd
import streamlit as st
import streamlit.components.v1 as components

# Import backend engines
from app.engine.mohamed_circle_kinematics import CircleKinematicsEngine
from app.engine.yousef_pit_and_flags_sync import PitAndFlagsSyncEngine
from app.engine.mahmud_weather_telemetry_sync import WeatherTelemetrySyncEngine


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
    """Load core dimensions from warehouse silver layer."""
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'exports', 'silver'))
    
    races_df = pd.read_csv(os.path.join(base_dir, 'dim_races.csv'))
    drivers_df = pd.read_csv(os.path.join(base_dir, 'dim_drivers.csv'))
    constructors_df = pd.read_csv(os.path.join(base_dir, 'dim_constructors.csv'))
    
    drivers_df['team_colour'] = drivers_df['team_colour'].astype(str).str.strip().str.upper()
    constructors_df['team_colour'] = constructors_df['team_colour'].astype(str).str.strip().str.upper()
    
    return races_df, drivers_df, constructors_df


@st.cache_data(show_spinner=False)
def load_session_telemetry(session_key: int):
    """Load fact tables for a specific Grand Prix session."""
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', 'exports', 'silver'))
    
    # Race Laps
    laps_path = os.path.join(base_dir, 'fact_race_laps.csv')
    laps_iter = pd.read_csv(laps_path, chunksize=25000)
    session_laps = pd.concat([chunk[chunk['session_key'] == session_key] for chunk in laps_iter])
    
    # Pit Stops
    pits_path = os.path.join(base_dir, 'fact_pit_stops.csv')
    pits_df = pd.read_csv(pits_path)
    session_pits = pits_df[pits_df['session_key'] == session_key]
    
    # Race Control
    rc_path = os.path.join(base_dir, 'fact_race_control.csv')
    rc_df = pd.read_csv(rc_path)
    session_rc = rc_df[rc_df['session_key'] == session_key]
    
    # Weather
    weather_path = os.path.join(base_dir, 'fact_weather.csv')
    weather_df = pd.read_csv(weather_path)
    session_weather = weather_df[weather_df['session_key'] == session_key]
    
    return session_laps, session_pits, session_rc, session_weather


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
    <div class="pitwall-title">RACE STATE SIMULATION <span>// VIRTUAL TRACK CIRCLE</span></div>
  </div>
  <div style="font-family: 'JetBrains Mono', monospace; font-size: 0.8rem; color: #8E9BAE;">
    WAREHOUSE: <span style="color: #00F0FF;">SILVER MEDALLION</span> | REPLAY ENGINE: <span style="color: #0066FF;">ACTIVE (60 FPS)</span>
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
    st.markdown("### SIMULATION CONTROLS")
    st.info("The central Virtual Track Circle runs in real-time with an interactive Play/Pause button, speed controls (1x to 10x), and live driver tracking.")


# Load Session Data & Initialize Engines
session_laps, session_pits, session_rc, session_weather = load_session_telemetry(session_key)

if session_laps.empty:
    st.error(f"[ERROR] No lap telemetry found for session {session_key}.")
    st.stop()

# Initialize Backend Engines
kinematics = CircleKinematicsEngine(session_laps, dim_drivers)
pit_flags = PitAndFlagsSyncEngine(session_pits, session_rc)
weather_sync = WeatherTelemetrySyncEngine(session_weather, race_meta)

max_laps = int(session_laps['lap_number'].max())
circuit_name = str(race_meta.iloc[0]['circuit_short_name']).upper()

# Pre-process lap-by-lap telemetry for ultra-fast, smooth client-side animation
lap_data_payload = {}
for lap_num, group in session_laps.groupby('lap_number'):
    d_list = []
    # Sort by position
    sorted_group = group.sort_values(by='position_end_of_lap')
    for _, row in sorted_group.iterrows():
        t_name = str(row.get('team_name', 'Unknown'))
        t_col = team_colors_map.get(t_name, '#3671C6')
        
        comp_str = str(row.get('compound', 'MEDIUM')).upper()
        comp_badge = comp_str[0] if comp_str in ['SOFT', 'MEDIUM', 'HARD', 'INTERMEDIATE', 'WET'] else 'M'
        
        d_list.append({
            'driver_number': int(row.get('driver_number', 0)),
            'acronym': str(row.get('name_acronym', 'DRV')),
            'team': t_name,
            'team_color': t_col,
            'pos': int(row.get('position_end_of_lap', 20)) if pd.notna(row.get('position_end_of_lap')) else 20,
            'duration': float(row.get('lap_duration', 90.0)) if pd.notna(row.get('lap_duration')) else 90.0,
            's1': float(row.get('duration_sector_1', 30.0)) if pd.notna(row.get('duration_sector_1')) else 30.0,
            's2': float(row.get('duration_sector_2', 30.0)) if pd.notna(row.get('duration_sector_2')) else 30.0,
            's3': float(row.get('duration_sector_3', 30.0)) if pd.notna(row.get('duration_sector_3')) else 30.0,
            'compound': comp_str,
            'compound_badge': comp_badge,
            'tyre_age': int(row.get('tyre_age_laps', 1)) if pd.notna(row.get('tyre_age_laps')) else 1,
            'is_pit_in': str(row.get('is_pit_in_lap', '')).lower() in ['true', 't', '1'],
            'is_pit_out': str(row.get('is_pit_out_lap', '')).lower() in ['true', 't', '1'],
            'speed': round(float(row.get('i1_speed', 280)) if pd.notna(row.get('i1_speed')) else 280.0, 1),
            'status': '[PIT]' if str(row.get('is_pit_in_lap', '')).lower() in ['true', 't', '1'] else '[ON_TRACK]'
        })
    lap_data_payload[int(lap_num)] = d_list


# Pre-process lap flags and weather states
flag_states_payload = {}
weather_states_payload = {}
for l in range(1, max_laps + 1):
    f_st = pit_flags.get_flag_state_at_lap(l)
    flag_states_payload[l] = {
        'flag': f_st['flag'],
        'badge': f_st['badge'],
        'track_color': f_st['track_color'],
        'glow_color': f_st['glow_color'],
        'message': f_st['message'],
        'recent_messages': f_st['recent_messages']
    }
    
    w_st = weather_sync.get_weather_at_lap_or_time(l, max_laps)
    weather_states_payload[l] = {
        'track_temp': w_st['track_temperature'],
        'air_temp': w_st['air_temperature'],
        'wind_speed': w_st['wind_speed'],
        'humidity': w_st['humidity'],
        'track_condition': w_st['track_condition'],
        'thermal_risk': w_st['thermal_risk'],
        'c_hard': w_st['c_hard'],
        'c_medium': w_st['c_medium'],
        'c_soft': w_st['c_soft']
    }

# Convert payload to JSON strings
race_json = json.dumps({
    'max_laps': max_laps,
    'circuit': circuit_name,
    'laps': lap_data_payload,
    'flags': flag_states_payload,
    'weather': weather_states_payload
})

# Complete Client-Side HTML5 / Canvas / SVG Real-Time Simulation App
simulation_html = f"""
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <link href="https://fonts.googleapis.com/css2?family=Titillium+Web:wght@300;400;600;700;900&family=JetBrains+Mono:wght@400;500;700&display=swap" rel="stylesheet">
  <style>
    * {{
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }}
    body {{
      background-color: #0B0C10;
      color: #FFFFFF;
      font-family: 'Titillium Web', sans-serif;
      overflow-x: hidden;
      padding: 10px;
    }}
    
    /* Playback & Scrub Bar */
    .playback-bar {{
      display: flex;
      align-items: center;
      justify-content: space-between;
      background: #12151E;
      border: 1px solid rgba(0, 240, 255, 0.2);
      border-radius: 6px;
      padding: 10px 18px;
      margin-bottom: 12px;
      box-shadow: 0 4px 15px rgba(0, 0, 0, 0.5);
    }}
    
    .btn-play {{
      background: linear-gradient(135deg, #00F0FF 0%, #0066FF 100%);
      color: #000000;
      border: none;
      border-radius: 4px;
      font-family: 'JetBrains Mono', monospace;
      font-weight: 800;
      font-size: 0.88rem;
      padding: 8px 18px;
      cursor: pointer;
      text-transform: uppercase;
      letter-spacing: 1px;
      transition: all 0.2s ease;
    }}
    .btn-play:hover {{
      box-shadow: 0 0 15px rgba(0, 240, 255, 0.6);
      transform: translateY(-1px);
    }}
    
    .scrubber-container {{
      flex: 1;
      margin: 0 20px;
      display: flex;
      flex-direction: column;
      gap: 4px;
    }}
    
    .scrubber-slider {{
      width: 100%;
      accent-color: #00F0FF;
      cursor: pointer;
    }}
    
    .speed-selector {{
      display: flex;
      gap: 6px;
      background: #080A0E;
      padding: 4px;
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
      font-size: 0.75rem;
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
      padding: 8px 16px;
      margin-bottom: 14px;
      border-radius: 4px;
      transition: border-color 0.3s ease;
    }}
    
    .flag-badge {{
      display: inline-block;
      padding: 4px 10px;
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
    .flag-badge.red {{ background: rgba(255, 23, 68, 0.2); color: #FF1744; border: 1px solid #FF1744; }}
    
    /* 3-Column Layout */
    .grid-container {{
      display: grid;
      grid-template-columns: 310px 1fr 280px;
      gap: 14px;
      align-items: start;
    }}
    
    /* Panel Cards */
    .card {{
      background: #12151E;
      border: 1px solid rgba(0, 240, 255, 0.15);
      border-radius: 6px;
      padding: 12px;
      box-shadow: 0 4px 16px rgba(0, 0, 0, 0.4);
    }}
    
    .card-title {{
      font-size: 0.8rem;
      font-weight: 700;
      letter-spacing: 1.2px;
      text-transform: uppercase;
      color: #8E9BAE;
      border-bottom: 1px solid rgba(0, 240, 255, 0.15);
      padding-bottom: 6px;
      margin-bottom: 10px;
    }}
    
    /* Timing Tower Table */
    .timing-table {{
      width: 100%;
      border-collapse: collapse;
      font-size: 0.82rem;
    }}
    .timing-table th {{
      color: #8E9BAE;
      font-size: 0.7rem;
      text-transform: uppercase;
      letter-spacing: 1px;
      padding: 6px 4px;
      border-bottom: 1px solid rgba(255, 255, 255, 0.1);
      text-align: left;
    }}
    .timing-table td {{
      padding: 5px 4px;
      border-bottom: 1px solid rgba(255, 255, 255, 0.04);
    }}
    .driver-pill {{
      display: flex;
      align-items: center;
      gap: 6px;
    }}
    .driver-tag {{
      width: 3.5px;
      height: 14px;
      border-radius: 1px;
    }}
    .acronym-text {{
      font-family: 'JetBrains Mono', monospace;
      font-weight: 700;
      color: #FFFFFF;
    }}
    .compound-badge {{
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 20px;
      height: 20px;
      border-radius: 50%;
      font-family: 'JetBrains Mono', monospace;
      font-weight: 900;
      font-size: 0.7rem;
    }}
    .compound-badge.S {{ background: #FF3333; color: #FFFFFF; }}
    .compound-badge.M {{ background: #FFD700; color: #000000; }}
    .compound-badge.H {{ background: #FFFFFF; color: #000000; }}
    .compound-badge.I {{ background: #00E676; color: #000000; }}
    .compound-badge.W {{ background: #0066FF; color: #FFFFFF; }}
    
    .status-tag {{
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.68rem;
      font-weight: 700;
      padding: 2px 5px;
      border-radius: 2px;
    }}
    .status-tag.pit {{
      background: rgba(0, 240, 255, 0.15);
      color: #00F0FF;
      border: 1px solid #00F0FF;
    }}
    
    /* Center Track Canvas Container */
    .track-canvas-container {{
      display: flex;
      justify-content: center;
      align-items: center;
      background: #080A0E;
      border: 1px solid rgba(0, 240, 255, 0.2);
      border-radius: 8px;
      padding: 10px;
      box-shadow: 0 0 25px rgba(0, 102, 255, 0.15);
      position: relative;
    }}
    
    /* Environmental & Ticker */
    .metric-grid {{
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 10px;
      margin-bottom: 12px;
    }}
    .metric-item {{
      background: #080A0E;
      padding: 8px;
      border-radius: 4px;
      border: 1px solid rgba(255, 255, 255, 0.05);
    }}
    .metric-label {{
      font-size: 0.68rem;
      color: #8E9BAE;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }}
    .metric-value {{
      font-family: 'JetBrains Mono', monospace;
      font-size: 1.15rem;
      font-weight: 700;
      color: #FFFFFF;
      margin-top: 2px;
    }}
    
    .ticker-box {{
      background: #080A0E;
      border: 1px solid rgba(0, 240, 255, 0.1);
      border-radius: 4px;
      padding: 8px;
      height: 160px;
      overflow-y: auto;
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.72rem;
      line-height: 1.4;
    }}
    .ticker-item {{
      margin-bottom: 6px;
      padding-bottom: 4px;
      border-bottom: 1px dashed rgba(255, 255, 255, 0.08);
      color: #CCD6E0;
    }}
  </style>
</head>
<body>

  <!-- Playback Control Bar -->
  <div class="playback-bar">
    <button id="btnPlay" class="btn-play">PLAY</button>
    
    <div class="scrubber-container">
      <div style="display: flex; justify-content: space-between; font-family: 'JetBrains Mono', monospace; font-size: 0.75rem; color: #8E9BAE;">
        <span>TIMELINE SCRUBBER</span>
        <span id="lapIndicator">LAP 1 / {max_laps}</span>
      </div>
      <input type="range" id="raceScrubber" class="scrubber-slider" min="1" max="{max_laps}" step="0.01" value="1">
    </div>
    
    <div class="speed-selector">
      <button class="btn-speed" data-speed="1">1x</button>
      <button class="btn-speed" data-speed="2">2x</button>
      <button class="btn-speed active" data-speed="5">5x</button>
      <button class="btn-speed" data-speed="10">10x</button>
    </div>
  </div>

  <!-- Session Status Banner -->
  <div id="statusBanner" class="status-banner">
    <div style="display: flex; align-items: center; gap: 12px;">
      <span id="flagBadge" class="flag-badge green">[GREEN]</span>
      <span id="flagMessage" style="font-weight: 700; font-size: 0.92rem; color: #FFFFFF;">TRACK CLEAR - ALL SECTORS GREEN</span>
    </div>
    <div style="font-family: 'JetBrains Mono', monospace; font-size: 0.82rem; color: #8E9BAE;">
      CIRCUIT: <span style="color: #00F0FF; font-weight: 700;">{circuit_name}</span> &nbsp;|&nbsp;
      ELAPSED: <span id="elapsedClock" style="color: #FFFFFF;">0m 00s</span>
    </div>
  </div>

  <!-- Main Grid Layout -->
  <div class="grid-container">
    
    <!-- LEFT: Live Timing Tower -->
    <div class="card">
      <div class="card-title">LIVE TIMING TOWER</div>
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
          <!-- Dynamically populated at 60 FPS -->
        </tbody>
      </table>
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

      <div style="margin-bottom: 12px; padding: 6px 8px; background: #080A0E; border-radius: 4px; display: flex; justify-content: space-between; font-size: 0.75rem;">
        <div>TRACK: <span id="valTrackState" style="color: #00E676; font-family: 'JetBrains Mono'; font-weight: bold;">[DRY]</span></div>
        <div>THERMAL: <span id="valThermal" style="color: #FFD700; font-family: 'JetBrains Mono'; font-weight: bold;">[OPTIMAL]</span></div>
      </div>

      <div class="card-title">PIRELLI ALLOCATION</div>
      <div id="pirelliAllocation" style="display: flex; gap: 6px; margin-bottom: 12px;">
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
    const raceData = {race_json};
    const maxLaps = raceData.max_laps;
    const lapsData = raceData.laps;
    const flagsData = raceData.flags;
    const weatherData = raceData.weather;

    // Simulation State
    let isPlaying = false;
    let currentLapFraction = 1.0;
    let playbackSpeed = 5.0; // 5x speed
    let lastTimestamp = performance.now();

    // DOM Elements
    const btnPlay = document.getElementById('btnPlay');
    const scrubber = document.getElementById('raceScrubber');
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
      btn.addEventListener('click', (e) => {{
        document.querySelectorAll('.btn-speed').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        playbackSpeed = parseFloat(btn.getAttribute('data-speed'));
      }});
    }});

    // Play/Pause Toggle
    btnPlay.addEventListener('click', () => {{
      isPlaying = !isPlaying;
      btnPlay.innerText = isPlaying ? 'PAUSE' : 'PLAY';
      btnPlay.style.background = isPlaying ? '#FFD700' : 'linear-gradient(135deg, #00F0FF 0%, #0066FF 100%)';
      if (isPlaying) {{
        lastTimestamp = performance.now();
      }}
    }});

    // Scrubber Drag
    scrubber.addEventListener('input', (e) => {{
      currentLapFraction = parseFloat(e.target.value);
      updateDisplay();
    }});

    // Polar to Cartesian Helper (0 deg at 12 o'clock)
    function pol2cart(r, deg) {{
      const rad = (deg - 90) * Math.PI / 180.0;
      return {{
        x: cx + r * Math.cos(rad),
        y: cy + r * Math.sin(rad)
      }};
    }}

    // Animation Loop (60 FPS)
    function animate(timestamp) {{
      const dt = (timestamp - lastTimestamp) / 1000.0; // seconds
      lastTimestamp = timestamp;

      if (isPlaying) {{
        // Advance lap progress: at 1x speed, 1 lap takes ~90s. With multiplier:
        const lapAdvance = (dt / 90.0) * playbackSpeed;
        currentLapFraction += lapAdvance;
        if (currentLapFraction > maxLaps) {{
          currentLapFraction = maxLaps;
          isPlaying = false;
          btnPlay.innerText = 'PLAY';
          btnPlay.style.background = 'linear-gradient(135deg, #00F0FF 0%, #0066FF 100%)';
        }}
        scrubber.value = currentLapFraction;
      }}

      updateDisplay();
      requestAnimationFrame(animate);
    }}

    // Update Telemetry, Canvas & Timing Tower
    function updateDisplay() {{
      const activeLap = Math.min(Math.max(Math.floor(currentLapFraction), 1), maxLaps);
      const lapProgress = currentLapFraction - activeLap; // [0, 1)

      lapIndicator.innerText = `LAP ${{activeLap}} / ${{maxLaps}}`;
      
      // Approximate Elapsed Clock
      const elapsedS = (currentLapFraction - 1) * 88.0;
      const mins = Math.floor(elapsedS / 60);
      const secs = Math.floor(elapsedS % 60);
      elapsedClock.innerText = `${{mins}}m ${{secs.toString().padStart(2, '0')}}s`;

      // Update Flag State
      const flagInfo = flagsData[activeLap] || {{ flag: 'GREEN', badge: '[GREEN]', track_color: '#0066FF', message: 'TRACK CLEAR' }};
      flagBadge.className = `flag-badge ${{flagInfo.flag.toLowerCase()}}`;
      flagBadge.innerText = flagInfo.badge;
      flagMessage.innerText = flagInfo.message;
      statusBanner.style.borderLeftColor = flagInfo.track_color;

      // Update Weather Telemetry
      const wInfo = weatherData[activeLap] || {{}};
      document.getElementById('valTrackTemp').innerText = `${{wInfo.track_temp || 35.0}}°C`;
      document.getElementById('valAirTemp').innerText = `${{wInfo.air_temp || 25.0}}°C`;
      document.getElementById('valWind').innerText = `${{wInfo.wind_speed || 2.0}} m/s`;
      document.getElementById('valHumidity').innerText = `${{wInfo.humidity || 50}}%`;
      document.getElementById('valTrackState').innerText = wInfo.track_condition || '[DRY]';
      document.getElementById('valThermal').innerText = wInfo.thermal_risk || '[OPTIMAL]';

      // Update Pirelli Allocation
      pirelliAllocation.innerHTML = `
        <span style="font-family: 'JetBrains Mono'; font-size: 0.75rem; padding: 2px 6px; border: 1px solid #FFFFFF; border-radius: 2px; color: #FFFFFF;">[H] ${{wInfo.c_hard || 'C1'}}</span>
        <span style="font-family: 'JetBrains Mono'; font-size: 0.75rem; padding: 2px 6px; border: 1px solid #FFD700; border-radius: 2px; color: #FFD700;">[M] ${{wInfo.c_medium || 'C2'}}</span>
        <span style="font-family: 'JetBrains Mono'; font-size: 0.75rem; padding: 2px 6px; border: 1px solid #FF3333; border-radius: 2px; color: #FF3333;">[S] ${{wInfo.c_soft || 'C3'}}</span>
      `;

      // Update Race Control Ticker
      const msgs = flagInfo.recent_messages || [];
      if (msgs.length > 0) {{
        tickerBox.innerHTML = msgs.slice().reverse().map(m => `<div class="ticker-item">${{m}}</div>`).join('');
      }} else {{
        tickerBox.innerHTML = '<div style="color: #536279; font-style: italic;">No active race control incidents.</div>';
      }}

      // Retrieve Drivers for Active Lap
      const drivers = lapsData[activeLap] || [];

      // Calculate Driver Positions & Angular Progress
      const computedDrivers = drivers.map(d => {{
        // Sector bounds
        const totalDur = d.duration || 90.0;
        const s1 = d.s1, s2 = d.s2, s3 = d.s3;
        const curT = lapProgress * totalDur;

        let deg = 0;
        let sector = 1;
        let isPit = false;

        if (curT < s1) {{
          sector = 1;
          deg = (curT / Math.max(s1, 0.1)) * 120.0;
          isPit = d.is_pit_out && (curT / s1 < 0.5);
        }} else if (curT < (s1 + s2)) {{
          sector = 2;
          deg = 120.0 + ((curT - s1) / Math.max(s2, 0.1)) * 120.0;
          isPit = false;
        }} else {{
          sector = 3;
          deg = 240.0 + ((curT - (s1 + s2)) / Math.max(s3, 0.1)) * 120.0;
          isPit = d.is_pit_in && ((curT - (s1 + s2)) / s3 > 0.4);
        }}

        // In-pit radial offset
        let r = rMain;
        if (isPit || (d.is_pit_in && deg >= 330) || (d.is_pit_out && deg <= 30)) {{
          r = rPit;
        }}

        return {{
          ...d,
          deg: deg % 360,
          radius: r,
          is_in_pit: isPit,
          distance_score: (activeLap - 1) + (deg / 360.0)
        }};
      }});

      // Sort by race distance score descending (Leader first)
      computedDrivers.sort((a, b) => b.distance_score - a.distance_score);

      // Render Timing Tower
      renderTimingTower(computedDrivers);

      // Render Virtual Track Circle Canvas
      renderCanvas(computedDrivers, flagInfo);
    }}

    // Render Live Timing Tower HTML Table
    function renderTimingTower(drivers) {{
      const leaderScore = drivers.length > 0 ? drivers[0].distance_score : 0;
      let html = '';

      drivers.forEach((d, idx) => {{
        const pos = idx + 1;
        let gapStr = 'LEADER';
        let intStr = '--';

        if (idx > 0) {{
          const gapScore = leaderScore - d.distance_score;
          const intScore = drivers[idx - 1].distance_score - d.distance_score;
          
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

        const statusTag = d.is_in_pit ? '<span class="status-tag pit">[PIT]</span>' : `<span style="color: #8E9BAE; font-size: 0.72rem;">${{d.speed}} km/h</span>`;

        html += `
          <tr>
            <td style="font-weight: 700; color: #FFFFFF;">${{pos}}</td>
            <td>
              <div class="driver-pill">
                <span class="driver-tag" style="background-color: ${{d.team_color}};"></span>
                <span class="acronym-text">${{d.acronym}}</span>
              </div>
            </td>
            <td style="font-family: 'JetBrains Mono'; font-size: 0.75rem; color: #8E9BAE;">${{gapStr}}</td>
            <td style="font-family: 'JetBrains Mono'; font-size: 0.75rem; color: #536279;">${{intStr}}</td>
            <td><span class="compound-badge ${{d.compound_badge}}">${{d.compound_badge}}</span></td>
            <td style="font-family: 'JetBrains Mono'; font-size: 0.75rem; text-align: center;">${{d.tyre_age}}</td>
            <td>${{statusTag}}</td>
          </tr>
        `;
      }});

      timingBody.innerHTML = html;
    }}

    // Render Canvas Dual-Ring Virtual Track Circle
    function renderCanvas(drivers, flagInfo) {{
      ctx.clearRect(0, 0, 600, 600);

      // Background Subtle Rings
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.03)';
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 4]);
      ctx.beginPath();
      ctx.arc(cx, cy, rMain + 35, 0, 2 * Math.PI);
      ctx.stroke();
      ctx.beginPath();
      ctx.arc(cx, cy, 140, 0, 2 * Math.PI);
      ctx.stroke();

      // Sector Divider Radial Lines
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
      const p1 = pol2cart(rPit, 330);
      const p2 = pol2cart(rPit, 30);
      ctx.strokeStyle = '#00F0FF';
      ctx.lineWidth = 2.5;
      ctx.setLineDash([6, 4]);
      // Arc from 330 (-120 rad) to 30 (-60 rad)
      ctx.arc(cx, cy, rPit, (330 - 90) * Math.PI / 180, (30 - 90) * Math.PI / 180);
      ctx.stroke();
      ctx.setLineDash([]);

      ctx.fillStyle = '#00F0FF';
      ctx.font = 'bold 9px "JetBrains Mono"';
      ctx.textAlign = 'center';
      ctx.fillText('PIT LANE [INNER RING]', cx, cy - rPit - 8);

      // Main Track Circle Glow & Body
      ctx.save();
      ctx.shadowColor = flagInfo.glow_color || 'rgba(0, 102, 255, 0.8)';
      ctx.shadowBlur = 18;
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

      // Start/Finish Line Marker (0 deg / 12 o'clock)
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
      ctx.strokeStyle = 'rgba(0, 240, 255, 0.3)';
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

      ctx.fillStyle = '#00F0FF';
      ctx.font = 'bold 12px "JetBrains Mono"';
      ctx.fillText(`LAP ${{Math.floor(currentLapFraction)}} / ${{maxLaps}}`, cx, cy + 22);

      // Render Dynamic Driver Nodes
      const compColors = {{
        'SOFT': '#FF3333',
        'MEDIUM': '#FFD700',
        'HARD': '#FFFFFF',
        'INTERMEDIATE': '#00E676',
        'WET': '#0066FF'
      }};

      drivers.forEach(d => {{
        const pt = pol2cart(d.radius, d.deg);
        const nodeRadius = 8.5;
        const tyreCol = compColors[d.compound] || '#FFD700';

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
        ctx.font = 'bold 7.5px "JetBrains Mono"';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(d.acronym, pt.x, pt.y + 0.5);

        // Pit Lane Badge
        if (d.is_in_pit) {{
          ctx.fillStyle = '#00F0FF';
          ctx.font = 'bold 8px "JetBrains Mono"';
          ctx.fillText('[PIT]', pt.x, pt.y - 12);
        }}
      }});
    }}

    // Start Simulation Animation
    requestAnimationFrame(animate);
  </script>
</body>
</html>
"""

# Render complete 60 FPS Canvas/SVG component
components.html(simulation_html, height=750, scrolling=False)
