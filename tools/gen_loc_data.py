"""Builds TemucraftLossOfControl data from Spell.dbc and SpellDuration.dbc (3.3.5a, 234 fields).

usage: python gen_loc_data.py <out.lua> <Spell.dbc> [more Spell.dbc ...] --duration <SpellDuration.dbc>
Later Spell.dbc files win for the same spell ID.
"""
import struct, sys

def read_dbc(path):
    data = open(path, 'rb').read()
    magic, rows, cols, size, strsize = struct.unpack_from('<4s4I', data, 0)
    assert magic == b'WDBC', path
    body = 20
    strings = data[body + rows * size:]
    out = []
    for r in range(rows):
        out.append(struct.unpack_from('<%dI' % cols, data, body + r * size))
    return out, strings

def string_at(strings, off):
    end = strings.find(b'\0', off)
    return strings[off:end].decode('utf-8', 'replace')

# Field positions (DBCStructure.h SpellEntry)
ID, MECHANIC, ATTR, DURATION = 0, 3, 4, 40
EFFECT, EFFECT_MECH, AURA, NAME = 71, 83, 95, 136
PASSIVE = 0x40
AURA_EFFECTS = {6, 27, 35, 65, 119, 128, 129, 143}
INTERRUPT_CAST = 68

# Label codes, kept in step with TemucraftLossOfControl.lua
CHARM, STUN, SAPPED, INCAP, FEAR, HORROR, POLY, DISORIENT, SLEEP, BANISH, SHACKLE, \
    SILENCE, PACIFY, PACIFYSILENCE, DISARM, ROOT, FREEZE, CONFUSE = range(1, 19)
PRIORITY = {CHARM: 100, STUN: 90, SAPPED: 90, INCAP: 90, SLEEP: 85, BANISH: 85, FEAR: 80, HORROR: 80,
            POLY: 80, DISORIENT: 80, SHACKLE: 80, CONFUSE: 80, PACIFYSILENCE: 70, SILENCE: 60,
            PACIFY: 55, DISARM: 40, FREEZE: 30, ROOT: 30}
BY_MECH = {30: SAPPED, 14: INCAP, 18: BANISH, 10: SLEEP, 17: POLY, 20: SHACKLE}

def classify(aura, mech):
    if aura in (2, 6, 128):
        return CHARM
    if aura == 12:
        return BY_MECH.get(mech, STUN)
    if aura == 7:
        return HORROR if mech == 24 else FEAR
    if aura == 5:
        if mech == 2:
            return DISORIENT
        return BY_MECH.get(mech, CONFUSE)
    if aura == 60:
        return PACIFYSILENCE
    if aura == 27:
        return SILENCE
    if aura == 25:
        return PACIFY
    if aura in (67, 254, 278):
        return DISARM
    if aura == 26:
        return FREEZE if mech == 13 else ROOT
    return None

def main():
    args = sys.argv[1:]
    out_path = args.pop(0)
    dur_path = args[args.index('--duration') + 1]
    spell_paths = args[:args.index('--duration')]
    durations = {row[0]: row[1] for row in read_dbc(dur_path)[0]}
    rows = {}
    names = {}
    for p in spell_paths:
        recs, strings = read_dbc(p)
        for row in recs:
            rows[row[ID]] = row
            names[row[ID]] = string_at(strings, row[NAME])
    spells, interrupts = {}, {}
    for sid, row in rows.items():
        if row[ATTR] & PASSIVE or not names[sid]:
            continue
        best = None
        for i in range(3):
            effect = row[EFFECT + i]
            if effect == INTERRUPT_CAST:
                ms = durations.get(row[DURATION], 0)
                if 0 < ms < 0x7fffffff:
                    interrupts[sid] = ms
            if effect not in AURA_EFFECTS:
                continue
            mech = row[EFFECT_MECH + i] or row[MECHANIC]
            code = classify(row[AURA + i], mech)
            if code and (best is None or PRIORITY[code] > PRIORITY[best]):
                best = code
        if best:
            spells[sid] = best
    with open(out_path, 'w', newline='\r\n') as f:
        f.write('-- Made by gen_loc_data.py from the Temucraft Spell.dbc. Do not edit by hand.\n')
        f.write('local _, ns = ...\n')
        f.write('ns.spells = {\n')
        items = sorted(spells.items())
        for i in range(0, len(items), 12):
            f.write('\t' + ' '.join('[%d]=%d,' % kv for kv in items[i:i + 12]) + '\n')
        f.write('}\n')
        f.write('ns.interrupts = {\n')
        items = sorted(interrupts.items())
        for i in range(0, len(items), 10):
            f.write('\t' + ' '.join('[%d]=%d,' % kv for kv in items[i:i + 10]) + '\n')
        f.write('}\n')
    counts = {}
    for c in spells.values():
        counts[c] = counts.get(c, 0) + 1
    print('spells', len(spells), 'interrupts', len(interrupts), 'by code', sorted(counts.items()))

if __name__ == '__main__':
    main()
