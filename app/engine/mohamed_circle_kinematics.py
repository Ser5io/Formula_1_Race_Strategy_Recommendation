"""
Module: mohamed_circle_kinematics.py
Team Member: Mohamed
Phase: Phase 3 - Race State Simulation & Virtual Track Circle
Objective: High-precision lap and sector kinematics interpolation engine.
           Converts continuous simulation timestamp into normalized lap progress p in [0, 1)
           and polar angle theta in [0, 2*pi) (0 to 360 degrees) around the Virtual Track Circle.
Constraints: Zero emojis. Strict text badges and mathematical rigor.
"""

import math
from typing import Dict, List, Optional, Any
import pandas as pd
import numpy as np


class CircleKinematicsEngine:
    """
    Computes angular position, track sector, current speed, and relative gap
    for every driver at any arbitrary simulation timestamp.
    """

    def __init__(self, laps_df: pd.DataFrame, drivers_df: Optional[pd.DataFrame] = None):
        """
        Initialize kinematics engine with facts from silver layer.
        """
        self.laps_df = laps_df.copy()
        
        # Ensure numerical types
        self.laps_df['lap_number'] = pd.to_numeric(self.laps_df['lap_number'], errors='coerce').fillna(0).astype(int)
        self.laps_df['driver_number'] = pd.to_numeric(self.laps_df['driver_number'], errors='coerce').fillna(0).astype(int)
        self.laps_df['lap_duration'] = pd.to_numeric(self.laps_df['lap_duration'], errors='coerce').fillna(90.0)
        
        # Sector durations
        self.laps_df['duration_sector_1'] = pd.to_numeric(self.laps_df['duration_sector_1'], errors='coerce')
        self.laps_df['duration_sector_2'] = pd.to_numeric(self.laps_df['duration_sector_2'], errors='coerce')
        self.laps_df['duration_sector_3'] = pd.to_numeric(self.laps_df['duration_sector_3'], errors='coerce')
        
        # Fallback for null sectors
        default_s = self.laps_df['lap_duration'] / 3.0
        self.laps_df['duration_sector_1'] = self.laps_df['duration_sector_1'].fillna(default_s)
        self.laps_df['duration_sector_2'] = self.laps_df['duration_sector_2'].fillna(default_s)
        self.laps_df['duration_sector_3'] = self.laps_df['duration_sector_3'].fillna(default_s)
        
        # Speeds
        self.laps_df['i1_speed'] = pd.to_numeric(self.laps_df.get('i1_speed', 280), errors='coerce').fillna(280)
        self.laps_df['i2_speed'] = pd.to_numeric(self.laps_df.get('i2_speed', 290), errors='coerce').fillna(290)
        self.laps_df['st_speed'] = pd.to_numeric(self.laps_df.get('st_speed', 315), errors='coerce').fillna(315)
        
        # Sort and calculate cumulative elapsed time per driver
        self.laps_df = self.laps_df.sort_values(by=['driver_number', 'lap_number']).reset_index(drop=True)
        self.laps_df['lap_end_time_s'] = self.laps_df.groupby('driver_number')['lap_duration'].cumsum()
        self.laps_df['lap_start_time_s'] = self.laps_df['lap_end_time_s'] - self.laps_df['lap_duration']
        
        # Sector time bounds
        self.laps_df['s1_end_s'] = self.laps_df['lap_start_time_s'] + self.laps_df['duration_sector_1']
        self.laps_df['s2_end_s'] = self.laps_df['s1_end_s'] + self.laps_df['duration_sector_2']
        self.laps_df['s3_end_s'] = self.laps_df['lap_end_time_s']
        
        # Driver metadata lookup
        self.drivers = self.laps_df['driver_number'].unique()
        self.max_laps = int(self.laps_df['lap_number'].max())
        self.total_race_duration_s = float(self.laps_df['lap_end_time_s'].max())

    def get_driver_state_at_time(self, driver_number: int, sim_time_s: float) -> Dict[str, Any]:
        """
        Calculates a driver's instantaneous angular progress theta, sector, speed, and status
        at simulation time `sim_time_s` (seconds from race start).
        """
        driver_laps = self.laps_df[self.laps_df['driver_number'] == driver_number]
        if driver_laps.empty:
            return {'status': '[OUT]', 'theta_rad': 0.0, 'theta_deg': 0.0, 'progress': 0.0}
        
        def _safe_int(val, default=1):
            try:
                if pd.isna(val) or val is None or val == '':
                    return default
                return int(float(val))
            except Exception:
                return default

        # Check if race has started for this driver
        first_lap = driver_laps.iloc[0]
        if sim_time_s < first_lap['lap_start_time_s']:
            # On starting grid (0 deg, 12 o'clock)
            return {
                'driver_number': driver_number,
                'name_acronym': first_lap.get('name_acronym', f'#{driver_number}'),
                'team_name': first_lap.get('team_name', 'Unknown'),
                'lap_number': 1,
                'progress': 0.0,
                'theta_rad': 0.0,
                'theta_deg': 0.0,
                'sector': 1,
                'speed_kmh': 0.0,
                'compound': str(first_lap.get('compound', 'MEDIUM')),
                'tyre_age': _safe_int(first_lap.get('tyre_age_laps'), 1),
                'is_pit': False,
                'status': '[GRID]'
            }
        
        # Check if driver has finished or retired before sim_time_s
        last_lap = driver_laps.iloc[-1]
        if sim_time_s >= last_lap['lap_end_time_s']:
            is_dnf = str(last_lap.get('race_condition', '')).upper() == 'DNF'
            status = '[DNF]' if is_dnf else '[FINISHED]'
            return {
                'driver_number': driver_number,
                'name_acronym': last_lap.get('name_acronym', f'#{driver_number}'),
                'team_name': last_lap.get('team_name', 'Unknown'),
                'lap_number': _safe_int(last_lap.get('lap_number'), 1),
                'progress': 1.0,
                'theta_rad': 0.0,
                'theta_deg': 0.0,
                'sector': 3,
                'speed_kmh': 0.0,
                'compound': str(last_lap.get('compound', 'HARD')),
                'tyre_age': _safe_int(last_lap.get('tyre_age_laps'), 1),
                'is_pit': False,
                'status': status
            }
            
        # Find active lap
        active_mask = (driver_laps['lap_start_time_s'] <= sim_time_s) & (sim_time_s < driver_laps['lap_end_time_s'])
        active_lap = driver_laps[active_mask]
        
        if active_lap.empty:
            # Fallback to closest lap
            active_lap = driver_laps.iloc[-1]
        else:
            active_lap = active_lap.iloc[0]
            
        # Interpolate within sectors
        # Sector 1: 0 deg to 120 deg (0 to 2*pi/3)
        # Sector 2: 120 deg to 240 deg (2*pi/3 to 4*pi/3)
        # Sector 3: 240 deg to 360 deg (4*pi/3 to 2*pi)
        
        s1_end = active_lap['s1_end_s']
        s2_end = active_lap['s2_end_s']
        s3_end = active_lap['s3_end_s']
        s0_start = active_lap['lap_start_time_s']
        
        is_pit_in = str(active_lap.get('is_pit_in_lap', '')).lower() in ['true', 't', '1']
        is_pit_out = str(active_lap.get('is_pit_out_lap', '')).lower() in ['true', 't', '1']
        
        if sim_time_s < s1_end:
            sector = 1
            dur = max(s1_end - s0_start, 0.001)
            frac = (sim_time_s - s0_start) / dur
            # Progress in sector 1: 0.0 to 0.3333
            progress = frac / 3.0
            theta_deg = progress * 360.0
            speed = float(active_lap.get('i1_speed', 280))
            is_pit = is_pit_out and (frac < 0.5)
        elif sim_time_s < s2_end:
            sector = 2
            dur = max(s2_end - s1_end, 0.001)
            frac = (sim_time_s - s1_end) / dur
            # Progress in sector 2: 0.3333 to 0.6666
            progress = (1.0 + frac) / 3.0
            theta_deg = progress * 360.0
            speed = float(active_lap.get('i2_speed', 295))
            is_pit = False
        else:
            sector = 3
            dur = max(s3_end - s2_end, 0.001)
            frac = (sim_time_s - s2_end) / dur
            # Progress in sector 3: 0.6666 to 1.0000
            progress = (2.0 + frac) / 3.0
            theta_deg = progress * 360.0
            speed = float(active_lap.get('st_speed', 315))
            # Pit lane entry is in sector 3 (usually > 330 deg)
            is_pit = is_pit_in and (frac > 0.5)
            
        theta_rad = math.radians(theta_deg)
        
        return {
            'driver_number': driver_number,
            'name_acronym': str(active_lap.get('name_acronym', f'#{driver_number}')),
            'full_name': str(active_lap.get('full_name', '')),
            'team_name': str(active_lap.get('team_name', 'Unknown')),
            'lap_number': _safe_int(active_lap.get('lap_number'), 1),
            'progress': float(progress),
            'theta_rad': float(theta_rad),
            'theta_deg': float(theta_deg),
            'sector': sector,
            'speed_kmh': round(speed, 1),
            'compound': str(active_lap.get('compound', 'MEDIUM')),
            'compound_code': str(active_lap.get('compound_code', '')),
            'tyre_age': _safe_int(active_lap.get('tyre_age_laps'), 1),
            'is_pit': bool(is_pit),
            'is_pit_in_lap': is_pit_in,
            'is_pit_out_lap': is_pit_out,
            'status': '[PIT]' if is_pit else '[ON_TRACK]',
            'deg_vs_stint_best_s': float(active_lap.get('deg_vs_stint_best_s', 0.0) or 0.0),
            'fuel_corrected_lap_time': float(active_lap.get('fuel_corrected_lap_time', 0.0) or 0.0)
        }

    def get_all_drivers_snapshot(self, sim_time_s: float) -> List[Dict[str, Any]]:
        """
        Returns kinematics snapshot for all drivers at sim_time_s, ordered by track position.
        Position is determined by cumulative laps completed + fractional lap progress.
        """
        snapshots = []
        for drv in self.drivers:
            state = self.get_driver_state_at_time(drv, sim_time_s)
            # Total race progress = (lap_number - 1) + progress
            state['total_distance_score'] = (state['lap_number'] - 1) + state['progress']
            snapshots.append(state)
            
        # Sort descending by distance score (leader first)
        snapshots.sort(key=lambda x: x['total_distance_score'], reverse=True)
        
        # Compute live running positions, gaps, and intervals
        leader_score = snapshots[0]['total_distance_score'] if snapshots else 0.0
        
        for i, s in enumerate(snapshots):
            s['position'] = i + 1
            if i == 0:
                s['gap_to_leader'] = 'LEADER'
                s['interval'] = '--'
            else:
                score_diff = leader_score - s['total_distance_score']
                ahead_diff = snapshots[i - 1]['total_distance_score'] - s['total_distance_score']
                
                # Approximate gap in seconds using leader's recent lap time
                lap_time_approx = 85.0
                gap_s = score_diff * lap_time_approx
                int_s = ahead_diff * lap_time_approx
                
                if score_diff >= 1.0:
                    laps_down = int(score_diff)
                    s['gap_to_leader'] = f'+{laps_down} LAP' if laps_down == 1 else f'+{laps_down} LAPS'
                else:
                    s['gap_to_leader'] = f'+{gap_s:.3f}s'
                    
                s['interval'] = f'+{int_s:.3f}s' if ahead_diff < 1.0 else f'+{int(ahead_diff)} LAP'
                
        return snapshots
