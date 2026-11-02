"""
Module: mahmud_weather_telemetry_sync.py
Team Member: Mahmud
Phase: Phase 3 - Race State Simulation & Virtual Track Circle
Objective: Weather & Track Evolution Telemetry Sync.
           Synchronizes silver.fact_weather, track temperature evolution, wind metrics,
           rainfall indicators, and Pirelli compound allocations (C_hard, C_medium, C_soft)
           with the simulation clock and active lap.
Constraints: Zero emojis. Strict text badges and telemetry accuracy.
"""

from typing import Dict, List, Optional, Any
import pandas as pd


class WeatherTelemetrySyncEngine:
    """
    Manages track and ambient environmental telemetry synchronization,
    calculates thermal degradation risk, and formats circuit compound allocations.
    """

    def __init__(
        self,
        weather_df: Optional[pd.DataFrame] = None,
        race_meta_df: Optional[pd.DataFrame] = None
    ):
        if weather_df is not None and not weather_df.empty:
            self.weather = weather_df.copy()
            self.weather['track_temperature'] = pd.to_numeric(self.weather.get('track_temperature', 35.0), errors='coerce').fillna(35.0)
            self.weather['air_temperature'] = pd.to_numeric(self.weather.get('air_temperature', 25.0), errors='coerce').fillna(25.0)
            self.weather['humidity'] = pd.to_numeric(self.weather.get('humidity', 50.0), errors='coerce').fillna(50.0)
            self.weather['wind_speed'] = pd.to_numeric(self.weather.get('wind_speed', 2.0), errors='coerce').fillna(2.0)
            self.weather['wind_direction'] = pd.to_numeric(self.weather.get('wind_direction', 180), errors='coerce').fillna(180)
            self.weather['rainfall'] = pd.to_numeric(self.weather.get('rainfall', 0), errors='coerce').fillna(0)
            if 'observed_at' in self.weather.columns:
                self.weather = self.weather.sort_values(by='observed_at').reset_index(drop=True)
        else:
            self.weather = pd.DataFrame()
            
        self.race_meta = race_meta_df.iloc[0].to_dict() if race_meta_df is not None and not race_meta_df.empty else {}

    def get_weather_at_lap_or_time(self, lap_progress: float, total_laps: int = 57) -> Dict[str, Any]:
        """
        Retrieves weather telemetry snapshot corresponding to the current lap progress.
        """
        if self.weather.empty:
            # Fallback realistic defaults
            return {
                'track_temperature': 38.5,
                'air_temperature': 27.2,
                'humidity': 52,
                'wind_speed': 2.8,
                'wind_direction': 165,
                'rainfall': 0,
                'is_raining': False,
                'rain_status': '[DRY]',
                'track_condition': '[DRY]',
                'thermal_risk': '[MODERATE]',
                'c_hard': self.race_meta.get('c_hard', 'C1'),
                'c_medium': self.race_meta.get('c_medium', 'C2'),
                'c_soft': self.race_meta.get('c_soft', 'C3')
            }
            
        # Map lap progress to weather record index
        frac = min(max(lap_progress / max(total_laps, 1), 0.0), 1.0)
        idx = int(frac * (len(self.weather) - 1))
        row = self.weather.iloc[idx]
        
        track_temp = float(row.get('track_temperature', 35.0))
        air_temp = float(row.get('air_temperature', 25.0))
        humidity = int(row.get('humidity', 50))
        wind_spd = float(row.get('wind_speed', 2.0))
        wind_dir = int(row.get('wind_direction', 180))
        rain_val = int(row.get('rainfall', 0))
        is_raining = bool(rain_val > 0 or row.get('is_raining', False))
        
        # Thermal risk classification
        if track_temp > 45.0:
            thermal_risk = '[CRITICAL_HIGH]'
        elif track_temp > 38.0:
            thermal_risk = '[ELEVATED]'
        elif track_temp < 25.0:
            thermal_risk = '[LOW_GRAINING]'
        else:
            thermal_risk = '[OPTIMAL]'
            
        return {
            'track_temperature': round(track_temp, 1),
            'air_temperature': round(air_temp, 1),
            'humidity': humidity,
            'wind_speed': round(wind_spd, 1),
            'wind_direction': wind_dir,
            'rainfall': rain_val,
            'is_raining': is_raining,
            'rain_status': '[WET]' if is_raining else '[DRY]',
            'track_condition': '[WET]' if is_raining else '[DRY]',
            'thermal_risk': thermal_risk,
            'c_hard': str(self.race_meta.get('c_hard', 'C1')),
            'c_medium': str(self.race_meta.get('c_medium', 'C2')),
            'c_soft': str(self.race_meta.get('c_soft', 'C3'))
        }

    def get_weather_series(self) -> List[Dict[str, Any]]:
        """
        Returns time-series telemetry points for mini-chart plotting across laps.
        """
        if self.weather.empty:
            return []
            
        series = []
        for i, row in self.weather.iterrows():
            series.append({
                'point': i,
                'track_temp': float(row.get('track_temperature', 35.0)),
                'air_temp': float(row.get('air_temperature', 25.0)),
                'wind_spd': float(row.get('wind_speed', 2.0)),
                'rainfall': int(row.get('rainfall', 0))
            })
        return series
