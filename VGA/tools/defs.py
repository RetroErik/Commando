"""Naming / grouping of the sprite records found in the data segment (identified by color, size and use in the code).

Confidence: 'high' = seen in game frames or referenced by code; 'medium' = inferred from appearance/position in the table.
"""

# (first offset, last offset inclusive) -> (group, label, confidence)
GROUPS = [
    (0x1B52, 0x1D66, 'enemy_dying', 'Enemy soldier hit / dying frames', 'medium'),
    (0x1E12, 0x3336 - 1, 'enemy_soldier', 'Enemy soldier (cyan) walk / aim / throw frames', 'high'),
    (0x3336, 0x3442, 'enemy_armsup', 'Enemy soldier arms raised', 'medium'),
    (0x3522, 0x3522, 'enemy_soldier', 'Enemy soldier (cyan) frame', 'high'),
    (0x36CC, 0x37D8, 'hero_cheer', 'Hero arms raised (celebration / hit)', 'medium'),
    (0x38B8, 0x3A0E, 'enemy_soldier', 'Enemy soldier (cyan) frame', 'high'),
    (0x3B64, 0x3D28, 'enemy_down', 'Enemy soldier crouched / lying frames', 'medium'),
    (0x3DAC, 0x4D34 - 1, 'hero', 'Hero (magenta) walk / aim frames', 'high'),
    (0x4D34, 0x517A, 'hero', 'Hero (magenta) walk / aim frames', 'high'),
    (0x52D0, 0x52D0, 'hero_down', 'Hero down / dead frame', 'medium'),
    (0x535C, 0x5468, 'hero_cheer', 'Hero arms raised (celebration / hit)', 'medium'),
    (0x5548, 0x5848, 'hero', 'Hero (magenta) walk / aim frames', 'high'),
    (0x599E, 0x5DD0, 'hero_fire', 'Hero firing frames (cyan muzzle detail)', 'medium'),
    (0x5F36, 0x61F6, 'side_art', 'Left / right decorative side-panel art (drawn 5x per side)', 'high'),
    (0x64B6, 0x7144, 'grenade_stock', 'Grenade stock pile shown in the score panel (table DS:1AF2: index 0 = blank, 1-9 = growing pile)', 'medium'),
    (0x739A, 0x739A, 'grenade', 'Thrown grenade', 'medium'),
    (0x73D8, 0x73D8, 'title_art', 'Hero seated on a crate (title / high-score artwork)', 'high'),
    (0x7B32, 0x7C9E, 'motorbike', 'Enemy motorbike with rider', 'high'),
    (0x7F74, 0x7F74, 'supply_crate', 'Supply / grenade crate pickup', 'medium'),
    (0x804A, 0x804A, 'bullet', 'Small bullet', 'high'),
    (0x8058, 0x810C, 'effect_burst', 'Hit sparks / small explosion', 'high'),
    (0x81E2, 0x81E2, 'effect_skull', 'Small skull / death mark', 'medium'),
    (0x8240, 0x83F4, 'effect_blast', 'Explosion / blood frames', 'medium'),
    (0x8478, 0x84AE, 'bullet', 'Enemy bullets', 'high'),
    (0x84DC, 0x84DC, 'jeep', 'Enemy jeep', 'high'),
    (0x88A2, 0x88A2, 'bullet', 'Bullet', 'medium'),
    (0x88BA, 0x88BA, 'gun_emplacement', 'Mortar / gun emplacement', 'medium'),
    (0x897C, 0x89D4, 'points', 'Bonus points pop-up (1000 / 2000)', 'high'),
    (0x8A68, 0x8A9E, 'bullet', 'Diagonal tracer bullets', 'medium'),
    (0x8AD4, 0x8AD4, 'cursor', 'Round cursor (high-score name entry)', 'high'),
    (0x8F5A, 0x8F5A, 'truck', 'Enemy truck', 'high'),
]
EXCLUDE = {0x0EF7, 0x9256}     # false positives (level data / zero-initialised work area)
EXTRA = [0x804A]              # tiny sprite that the generic scan skips


def classify(d):
    for lo, hi, grp, label, conf in GROUPS:
        if lo <= d <= hi:
            return grp, label, conf
    return 'unknown', 'Unclassified sprite', 'low'

