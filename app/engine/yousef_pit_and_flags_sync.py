"""
Module: yousef_pit_and_flags_sync.py
Team Member: Yousef
Phase: Phase 3 - Race State Simulation & Virtual Track Circle
Objective: Pit Lane Inner-Ring Geometry & FIA Flag State Machine.
           Synchronizes fact_pit_stops and fact_race_control with the simulation clock.
           Calculates radial coordinate r = R_pit (0.82 * R_track) for cars in the pit lane,
           computes track glow colors based on active FIA flag state, and maintains pit loss telemetry.
Constraints: Zero emojis. Strict text badges and mathematical rigor.
"""

from typing import Dict, List, Optional, Tuple, Any
import pandas as pd


class PitAndFlagsSyncEngine:
    """
    Manages pit lane entry/exit transitions, inner-ring radial displacements,
    and FIA Race Control flag states.
    """

    def __init__(
        self,
        pit_stops_df: Optional[pd.DataFrame] = None,
        race_control_df: Optional[pd.DataFrame] = None,
        base_track_radius: float = 240.0
    ):
        self.base_track_radius = base_track_radius
        self.pit_lane_radius = 0.82 * base_track_radius  # Radius offset R_pit = 0.82 * R_track
        
        # Process pit stops
        if pit_stops_df is not None and not pit_stops_df.empty:
            self.pit_stops = pit_stops_df.copy()
            self.pit_stops['lap_number'] = pd.to_numeric(self.pit_stops['lap_number'], errors='coerce').fillna(0).astype(int)
            self.pit_stops['driver_number'] = pd.to_numeric(self.pit_stops['driver_number'], errors='coerce').fillna(0).astype(int)
            self.pit_stops['lane_duration'] = pd.to_numeric(self.pit_stops['lane_duration'], errors='coerce').fillna(20.0)
            self.pit_stops['stop_duration'] = pd.to_numeric(self.pit_stops['stop_duration'], errors='coerce').fillna(2.5)
            self.pit_stops['net_pit_loss_s'] = pd.to_numeric(self.pit_stops.get('net_pit_loss_s', 21.0), errors='coerce').fillna(21.0)
        else:
            self.pit_stops = pd.DataFrame()
            
        # Process race control
        if race_control_df is not None and not race_control_df.empty:
            self.race_control = race_control_df.copy()
            self.race_control['lap_number'] = pd.to_numeric(self.race_control['lap_number'], errors='coerce').fillna(0).astype(int)
            # Sort chronologically
            if 'event_at' in self.race_control.columns:
                self.race_control = self.race_control.sort_values(by='event_at').reset_index(drop=True)
        else:
            self.race_control = pd.DataFrame()

    def get_driver_radius(
        self,
        is_in_pit_lane: bool,
        theta_deg: float,
        is_pit_in_lap: bool = False,
        is_pit_out_lap: bool = False
    ) -> Tuple[float, str]:
        """
        Calculates driver radial coordinate R.
        Pit lane spans 330 deg through 0 deg to 30 deg on inner radius.
        """
        # Inner pit lane arc: 330 deg to 360 deg and 0 deg to 30 deg
        in_pit_arc = (theta_deg >= 330.0) or (theta_deg <= 30.0)
        
        if is_in_pit_lane or (is_pit_in_lap and theta_deg >= 320.0) or (is_pit_out_lap and theta_deg <= 35.0):
            # Smooth blend into inner radius if entering or exiting
            if theta_deg >= 320.0 and theta_deg < 330.0:
                blend = (theta_deg - 320.0) / 10.0
                r = self.base_track_radius - blend * (self.base_track_radius - self.pit_lane_radius)
                return r, '[PIT_ENTRY]'
            elif theta_deg > 30.0 and theta_deg <= 40.0:
                blend = (40.0 - theta_deg) / 10.0
                r = self.base_track_radius - blend * (self.base_track_radius - self.pit_lane_radius)
                return r, '[PIT_EXIT]'
            else:
                return self.pit_lane_radius, '[PIT_LANE]'
                
        return self.base_track_radius, '[MAIN_TRACK]'

    def get_flag_state_at_lap(self, lap_number: int) -> Dict[str, Any]:
        """
        Determines current FIA Flag status for a given lap number.
        Returns flag code, display badge, track border color, and glow effects.
        """
        if self.race_control.empty:
            return {
                'flag': 'GREEN',
                'badge': '[GREEN]',
                'track_color': '#0066FF',
                'glow_color': 'rgba(0, 240, 255, 0.6)',
                'message': 'TRACK CLEAR - ALL SECTORS GREEN',
                'recent_messages': []
            }
            
        # Get messages up to this lap
        past_rc = self.race_control[self.race_control['lap_number'] <= lap_number]
        
        if past_rc.empty:
            return {
                'flag': 'GREEN',
                'badge': '[GREEN]',
                'track_color': '#0066FF',
                'glow_color': 'rgba(0, 240, 255, 0.6)',
                'message': 'TRACK CLEAR - ALL SECTORS GREEN',
                'recent_messages': []
            }
            
        # Recent 5 messages for ticker
        recent_msgs = []
        for _, row in past_rc.tail(5).iterrows():
            badge = f"[{str(row.get('category', 'RC')).upper()}]"
            msg = str(row.get('message', ''))
            recent_msgs.append(f"Lap {int(row.get('lap_number', 0))}: {badge} {msg}")
            
        # Find active safety car or red flag state
        # Filter for recent events (within 3 laps or active messages)
        active_events = past_rc[past_rc['lap_number'] >= max(1, lap_number - 2)]
        
        def _check_flag_col(col_name):
            if col_name not in active_events.columns:
                return False
            vals = active_events[col_name].dropna().astype(str).str.lower()
            return any(v in ['t', 'true', '1'] for v in vals)

        is_red = _check_flag_col('is_red_flag_event')
        is_sc = _check_flag_col('is_sc_event')
        is_vsc = _check_flag_col('is_vsc_event')
        
        # Check text in messages for active condition
        latest_msg = str(past_rc.iloc[-1].get('message', '')).upper()
        latest_flag = str(past_rc.iloc[-1].get('flag', '')).upper()
        
        if 'RED' in latest_flag or 'RED FLAG' in latest_msg or is_red:
            return {
                'flag': 'RED',
                'badge': '[RED]',
                'track_color': '#FF0033',
                'glow_color': 'rgba(255, 0, 51, 0.8)',
                'message': 'SESSION SUSPENDED - RED FLAG',
                'recent_messages': recent_msgs
            }
        elif 'SAFETY CAR DEPLOYED' in latest_msg or 'SAFETY CAR' in latest_msg or is_sc:
            return {
                'flag': 'SC',
                'badge': '[SC]',
                'track_color': '#FFD700',
                'glow_color': 'rgba(255, 215, 0, 0.8)',
                'message': 'SAFETY CAR DEPLOYED',
                'recent_messages': recent_msgs
            }
        elif 'VIRTUAL SAFETY CAR' in latest_msg or 'VSC' in latest_msg or is_vsc:
            return {
                'flag': 'VSC',
                'badge': '[VSC]',
                'track_color': '#FFB700',
                'glow_color': 'rgba(255, 183, 0, 0.8)',
                'message': 'VIRTUAL SAFETY CAR DEPLOYED',
                'recent_messages': recent_msgs
            }
        elif 'YELLOW' in latest_msg:
            return {
                'flag': 'YELLOW',
                'badge': '[YELLOW]',
                'track_color': '#FFEA00',
                'glow_color': 'rgba(255, 234, 0, 0.7)',
                'message': 'TRACK HAZARD - YELLOW FLAG',
                'recent_messages': recent_msgs
            }
        else:
            return {
                'flag': 'GREEN',
                'badge': '[GREEN]',
                'track_color': '#0066FF',
                'glow_color': 'rgba(0, 240, 255, 0.6)',
                'message': 'TRACK CLEAR - ALL SECTORS GREEN',
                'recent_messages': recent_msgs
            }

    def get_pit_stop_history(self, driver_number: int) -> List[Dict[str, Any]]:
        """
        Returns all historical pit stops for a specific driver.
        """
        if self.pit_stops.empty:
            return []
            
        driver_pits = self.pit_stops[self.pit_stops['driver_number'] == driver_number]
        results = []
        for _, row in driver_pits.iterrows():
            results.append({
                'lap': int(row.get('lap_number', 0)),
                'stop_duration_s': float(row.get('stop_duration', 0.0)),
                'lane_duration_s': float(row.get('lane_duration', 0.0)),
                'net_loss_s': float(row.get('net_pit_loss_s', 0.0)),
                'is_penalty': bool(row.get('is_penalty_stop', False))
            })
        return results
