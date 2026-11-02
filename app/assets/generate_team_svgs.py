import os
import re

teams = {
    'Red Bull Racing': ('#3671C6', 'RBR'),
    'Ferrari': ('#E8002D', 'FER'),
    'Mercedes': ('#27F4D2', 'MER'),
    'McLaren': ('#FF8000', 'MCL'),
    'Aston Martin': ('#229971', 'AMR'),
    'Alpine': ('#FF87BC', 'ALP'),
    'Williams': ('#64C4FF', 'WIL'),
    'RB': ('#6692FF', 'RBF'),
    'Racing Bulls': ('#6692FF', 'RBF'),
    'Kick Sauber': ('#52E252', 'SAU'),
    'Haas F1 Team': ('#B6BABD', 'HAS'),
    'Alfa Romeo': ('#C92D4B', 'ALF'),
    'AlphaTauri': ('#5E8FAA', 'ALT')
}

os.makedirs('app/assets/teams', exist_ok=True)

for team, (color, code) in teams.items():
    slug = re.sub(r'[^a-zA-Z0-9]', '_', team.lower())
    svg_content = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 24" width="64" height="24">
  <rect width="64" height="24" rx="3" fill="#12151E" stroke="{color}" stroke-width="1.5"/>
  <text x="32" y="16" fill="#FFFFFF" font-family="Arial, sans-serif" font-size="11" font-weight="bold" text-anchor="middle" letter-spacing="0.5">{code}</text>
  <circle cx="8" cy="12" r="3.5" fill="{color}"/>
</svg>'''
    with open(f'app/assets/teams/{slug}.svg', 'w') as f:
        f.write(svg_content)

print(f"Generated SVGs for {len(teams)} teams.")
