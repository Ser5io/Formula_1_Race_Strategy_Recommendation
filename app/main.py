"""
Module: main.py
Phase: Phase 3 & Phase 4 Entry Point
Objective: Pit-Wall Strategist Computer & Race State Simulation Launchpad
Theme: Matte Black (#0B0C10) and Electric Blue (#00F0FF)
Constraints: Zero emojis. Strict text badges.
"""

import sys
import os

# Ensure project root is in sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

# Run page 01 directly
import app.pages.01_race_state_replay
