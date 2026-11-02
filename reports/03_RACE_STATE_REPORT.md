# PHASE 3 AUDIT REPORT: RACE STATE TIMELINE REPLAY & VIRTUAL TRACK CIRCLE

**Repository**: `Formula_1_Race_Strategy_Recommendation`  
**Phase**: Phase 3 - Race State Simulation & Chronological Replay ("From Lights Out to Chequered Flag")  
**Design Theme**: Matte Black (`#0B0C10`, `#12151E`) & Electric Pit-Wall Blue (`#00F0FF`, `#0066FF`, `#0033AA`)  
**Compliance**: Zero Emojis, Strict Text Badges (`[S]`, `[M]`, `[H]`, `[I]`, `[W]`, `[PIT]`, `[GREEN]`, `[SC]`, `[VSC]`, `[RED]`), Vector SVGs, Official F1 & Constructor Logos  

---

## 1. Executive Summary & Architecture Overview

Phase 3 implements the interactive **Race State Replay and Virtual Track Circle Simulation Engine**. The system reconstructs the full chronological state of every Formula 1 race across the 2023, 2024, and 2025 seasons from the warehouse's Silver layer (`silver.fact_race_laps`, `silver.fact_pit_stops`, `silver.fact_race_control`, `silver.fact_weather`, `silver.dim_races`, `silver.dim_drivers`, `silver.dim_constructors`).

The simulation features:
1. **Virtual Track Circle (Dual-Ring 2D/SVG)**:
   - High-contrast circular track ($R_{\text{main}} = 220\text{px}$) with sector dividers: Sector 1 ($0^\circ - 120^\circ$), Sector 2 ($120^\circ - 240^\circ$), Sector 3 ($240^\circ - 360^\circ$).
   - Dynamic Start/Finish line marker at $0^\circ$ (12 o'clock position).
   - Inner Pit-Lane Ring ($R_{\text{pit}} = 0.82 \cdot R_{\text{main}} = 180\text{px}$) spanning $330^\circ$ through $0^\circ$ to $30^\circ$ where cars pull in during pit stops.
   - Dynamic track glow responding to FIA race flags: `#0066FF` (Green), `#FFD700` (Yellow/SC/VSC), `#FF0033` (Red Flag).
2. **Dynamic Driver Nodes**:
   - Each driver is positioned at exact polar angle $\theta(t)$ and radial coordinate $R(t)$.
   - Outer compound ring colored strictly by tyre compound (`[S]` Red `#FF3333`, `[M]` Yellow `#FFD700`, `[H]` White `#FFFFFF`, `[I]` Green `#00E676`, `[W]` Blue `#0066FF`).
   - Inner circular node filled with the official constructor hex code from `silver.dim_constructors`.
   - Centered 3-letter driver acronym (`VER`, `NOR`, `LEC`, `HAM`, etc.) rendered in JetBrains Mono.
3. **Live Pit-Wall Timing Tower**:
   - Ordered in real-time by continuous track position ($(\text{lap} - 1) + p$).
   - Displays position, constructor color bar, acronym, gap to leader, interval to car ahead, tyre compound badge, tyre age (laps), and live status (`[PIT]`, `[DNF]`, or speed trap km/h).
4. **Environmental & FIA Race Control HUD**:
   - Synchronized track temperature, air temperature, wind speed, humidity, and track condition (`[DRY]` / `[WET]`).
   - Pirelli circuit compound allocation (`C_hard`, `C_medium`, `C_soft`).
   - Real-time scrolling FIA Race Control messages ticker.

---

## 2. Team Member Allocation & Deliverables

| Team Member | Module / Script | Role & Key Contributions |
|---|---|---|
| **Mohamed** | `sql/03_race_state/01_mohamed_virtual_circle_telemetry.sql`<br>`app/engine/mohamed_circle_kinematics.py` | Built the SQL telemetry view `silver.vw_race_state_timeline` with cumulative race elapsed time and leader gap CTEs. Developed the high-precision polar kinematics engine interpolating continuous timestamp $t$ into sector progress and angle $\theta \in [0, 360^\circ)$. |
| **Yousef** | `app/engine/yousef_pit_and_flags_sync.py` | Implemented pit stop synchronization, inner pit-lane radius offset logic ($R_{\text{pit}} = 0.82 \cdot R_{\text{track}}$) spanning $330^\circ - 30^\circ$, and the FIA Flag State Machine managing dynamic track border colors and glow effects. |
| **Mahmud** | `app/engine/mahmud_weather_telemetry_sync.py` | Developed weather telemetry synchronization linking `silver.fact_weather` to lap progression, thermal risk classification, and circuit Pirelli compound allocations (`C_hard`, `C_medium`, `C_soft`). |
| **Moaz** | `app/styles/pitwall_black_blue.css`<br>`app/pages/01_race_state_replay.py`<br>`app/main.py`<br>`reports/03_RACE_STATE_REPORT.md` | Designed the Matte Black & Electric Pit-Wall Blue CSS styling, assembled the interactive Streamlit UI, rendered the 2D/SVG Dual-Ring Virtual Track Circle, integrated the live timing tower, and authored the Phase 3 report. |

---

## 3. Mathematical & Kinematic Formulations

### 3.1 Angular Progress & Position Interpolation
For driver $i$ at simulation timestamp $t \in [t_{\text{start}}, t_{\text{end}}]$ within lap $L$:
$$\Delta t_L = t - t_{\text{lap\_start}}$$

The lap is divided into three physical timing sectors:
- **Sector 1** ($0^\circ$ to $120^\circ$, duration $D_{S1}$):
  $$p = \frac{\Delta t_L}{3 \cdot D_{S1}}, \quad \theta = 360^\circ \cdot p$$
- **Sector 2** ($120^\circ$ to $240^\circ$, duration $D_{S2}$):
  $$p = \frac{1}{3} + \frac{\Delta t_L - D_{S1}}{3 \cdot D_{S2}}, \quad \theta = 360^\circ \cdot p$$
- **Sector 3** ($240^\circ$ to $360^\circ$, duration $D_{S3}$):
  $$p = \frac{2}{3} + \frac{\Delta t_L - (D_{S1} + D_{S2})}{3 \cdot D_{S3}}, \quad \theta = 360^\circ \cdot p$$

Polar coordinates are mapped to 2D Cartesian display coordinates with center $(C_x, C_y) = (300, 300)$:
$$x = C_x + R(t) \cdot \cos\left(\theta - \frac{\pi}{2}\right)$$
$$y = C_y + R(t) \cdot \sin\left(\theta - \frac{\pi}{2}\right)$$

### 3.2 Radial Displacement for Pit Lane
When a car is in the pit lane ($t \in [t_{\text{pit\_in}}, t_{\text{pit\_out}}]$):
$$R(t) = 0.82 \cdot R_{\text{main}} = 180\text{px}$$
Smooth entry and exit transitions occur between $320^\circ - 330^\circ$ and $30^\circ - 40^\circ$.

---

## 4. Race State Transition Verification (Session 7779 Sample)

| Metric / Parameter | Value Observed | Validation Status |
|---|---|---|
| Total Competing Drivers | 20 | Verified |
| Track Sectors | 3 Sectors ($120^\circ$ each) | Verified |
| Pit Lane In-Ring Radius | $R_{\text{pit}} = 180\text{px}$ ($0.82 \times 220\text{px}$) | Verified |
| Active Safety Car Flags Handled | `[GREEN]`, `[YELLOW]`, `[SC]`, `[VSC]`, `[RED]` | Verified |
| Compound Badges Supported | `[S]`, `[M]`, `[H]`, `[I]`, `[W]` | Verified |
| Emoji Audit | 0 emojis detected across all UI and code modules | Verified |
