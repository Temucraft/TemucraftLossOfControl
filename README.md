# Temucraft Loss of Control

A retail-style alert for WoW 3.3.5a when something controls your character: stunned, feared, charmed, polymorphed, asleep, sapped, silenced, pacified, disarmed, rooted, and school lockouts after an interrupt.

The spell list (`Data.lua`) is made from the Temucraft Spell.dbc by `tools/gen_loc_data.py`, so new Temucraft spells are covered. Run it again after the DBC changes:

```
python tools/gen_loc_data.py TemucraftLossOfControl/Data.lua <dbc>/Spell.dbc <patch>/Spell.dbc --duration <dbc>/SpellDuration.dbc
```

`/tloc` opens the options. `/tloc move`, `/tloc lock`, `/tloc reset`.
