#!/usr/bin/env python3
"""Build ios/Upscroll/Resources/vocab.json: hand-made entries + JLPT N5…N1 lists, each with a level.

    python3 tools/build_vocab.py            # also compiles and runs tools/romaji.swift

Hand-made entries (tools/data/curated.json) keep their ids, English forms, part of speech and emoji;
they only gain a `level`. JLPT words get English forms derived from their glosses.
`level` is the JLPT number: 5 = N5 (easiest) … 1 = N1.
"""
import csv, json, re, subprocess, sys, unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT.parent / "ios/Upscroll/Resources/vocab.json"
CURATED = ROOT / "data/curated.json"

# English words too common or vague to swap from a JLPT gloss (hand-made entries handle the useful ones).
STOP = set("""a an the and or but if so as at by for from in into of on onto to up with without about over under
it its this that these those there here he she they we you i me my your his her their our them us him
be is are was were been being am do does did done have has had get got make made go come take give put set
one thing things way part kind sort lot bit time like just well right really very much many more most some any
all no not yes oh ah okay ok also too only even still yet then now again back out off down good bad new old
can could will would should may might must shall let say said tell see look use used work need want know""".split())

KATA = re.compile(r"^[゠-ヿ・ー]+$")

def is_kata(s): return bool(KATA.match(s))

def glosses(meaning):
    """'to meet, to see; to encounter' → ['to meet', 'to see', 'to encounter'] (parentheticals dropped)."""
    m = re.sub(r"\([^)]*\)|\[[^\]]*\]", "", meaning)
    return [g.strip(" .!?\"'") for g in re.split(r"[;,/]", m) if g.strip(" .!?\"'")]

def pos_of(expr, reading, gl):
    if gl and all(g.startswith("to ") for g in gl[:1]): return "verb"
    if reading.endswith("い") and expr.endswith("い") and not is_kata(reading) and not gl[0].startswith("to "): return "adj"
    return "any"   # nouns / na-adjectives / adverbs: Jev's sense check decides in context

def forms_of(gl, pos):
    out = []
    for g in gl[:2]:
        g = g.lower()
        if pos == "verb": g = re.sub(r"^to ", "", g)
        g = re.sub(r"^(a|an|the) ", "", g)
        words = g.split()
        if not (1 <= len(words) <= 2) or not all(re.fullmatch(r"[a-z][a-z'-]*", w) for w in words): continue
        if len(words) == 1 and (g in STOP or len(g) < 3): continue
        if len(words) == 2 and (words[0] in STOP or words[1] in STOP): continue   # "demand for", "the key"
        if g not in out: out.append(g)
    return out[:2]   # rarer senses come later in the gloss; Jev still sense-checks each use

def short_meaning(gl, raw):
    gl = [re.sub(r"^(a|an|the) ", "", g) for g in gl]
    m = ", ".join(gl[:2]) if gl else raw
    return m if len(m) <= 40 else m[:38].rsplit(" ", 1)[0] + "…"

def main():
    curated = json.loads(CURATED.read_text())
    rows = []   # (level, expr, reading, meaning)
    for lv in (5, 4, 3, 2, 1):
        with open(ROOT / f"data/jlpt/n{lv}.csv", newline="", encoding="utf-8") as f:
            for r in csv.DictReader(f):
                # "練習 / れんしゅう (する)" → the word itself; the (する) note isn't part of it.
                strip = lambda t: re.sub(r"\s*[（(][^)）]*[)）]\s*", "", t).strip()
                expr, reading = strip(r["expression"]), strip(r["reading"])
                if expr and reading: rows.append((lv, unicodedata.normalize("NFC", expr), unicodedata.normalize("NFC", reading), r["meaning"].strip()))

    # Easiest level wins for words listed at several levels.
    level_of = {}
    for lv, expr, reading, _ in rows:
        for k in (expr, reading):
            level_of[k] = max(level_of.get(k, 0), lv)

    out, seen_ids, seen_words = [], set(), set()
    for e in curated:   # hand-made first: their English forms take priority
        e = dict(e)
        e["level"] = level_of.get(e.get("kanji") or "", 0) or level_of.get(e["kana"], 0) or 5
        out.append(e); seen_ids.add(e["id"])
        seen_words.update({e["kana"], e.get("kanji") or e["kana"]})

    for lv, expr, reading, meaning in rows:
        if expr in seen_words or (expr == reading and reading in seen_words): continue
        seen_words.add(expr)
        gl = glosses(meaning)
        if not gl: continue
        pos = pos_of(expr, reading, gl)
        eid = "jp:" + expr + ("" if expr == reading else "|" + reading)
        if eid in seen_ids: continue
        seen_ids.add(eid)
        out.append({
            "id": eid, "en": forms_of(gl, pos), "kana": reading,
            "kanji": None if expr == reading else expr, "romaji": "",
            "meaning": short_meaning(gl, meaning), "loanword": is_kata(reading),
            "pos": pos, "emoji": "", "level": level_of.get(expr, lv),
        })

    OUT.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")))
    # Romaji with the same ICU transform the app uses (Kana.romaji), for entries that lack it.
    # (compiled with xcrun swiftc: `swift script.swift` breaks when the CLI and Xcode toolchains differ)
    import tempfile
    exe = Path(tempfile.gettempdir()) / "upscroll-romaji"
    subprocess.run(["xcrun", "--sdk", "macosx", "swiftc", "-O", str(ROOT / "romaji.swift"), "-o", str(exe)], check=True)
    subprocess.run([str(exe), str(OUT)], check=True)
    by = {}
    for e in json.loads(OUT.read_text()): by[e["level"]] = by.get(e["level"], 0) + 1
    print(f"{OUT.name}: {sum(by.values())} words", {f"N{k}": v for k, v in sorted(by.items(), reverse=True)})

if __name__ == "__main__":
    main()
