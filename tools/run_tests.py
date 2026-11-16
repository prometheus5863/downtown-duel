"""Runs every tests/test_*.gd headless and summarises PASS / FAIL.
   Run: python tools/run_tests.py [project_dir] [name-filter]
   Godot is taken from $GODOT, else C:/Godot/Godot_v4.7.2-stable_win64_console.exe, else `godot` on PATH."""
import glob, os, subprocess, sys
P = sys.argv[1] if len(sys.argv) > 1 else "."
FILTER = sys.argv[2] if len(sys.argv) > 2 else ""
GODOT = os.environ.get("GODOT") or next(
    (g for g in ["C:/Godot/Godot_v4.7.2-stable_win64_console.exe"] if os.path.exists(g)), "godot")
bad = 0
for t in sorted(glob.glob(os.path.join(P, "tests", "test_*.gd"))):
    name = os.path.basename(t)
    if FILTER and FILTER not in name:
        continue
    try:
        r = subprocess.run([GODOT, "--headless", "--path", P, "-s", "res://tests/" + name],
                           capture_output=True, text=True, timeout=600)
        out, code = r.stdout + r.stderr, r.returncode
    except subprocess.TimeoutExpired as e:
        out, code = (e.stdout or "") + "\nTIMEOUT", 1
    lines = out.splitlines()
    fails = [l for l in lines if l.startswith("FAIL ")]
    errors = [l for l in lines if l.startswith(("SCRIPT ERROR", "ERROR:"))]
    passes = sum(l.startswith("PASS") for l in lines)
    ok = code == 0 and not fails and not errors and passes > 0
    print(f"{'ok  ' if ok else 'FAIL'} {name}: {passes} passed, {len(fails)} failed, {len(errors)} engine errors")
    for l in fails + errors[:10]:
        print("     ", l)
    if not ok and not fails and not errors:
        print("\n".join("      " + l for l in lines[-15:]))
    bad += not ok
print("ALL TESTS PASSED" if not bad else f"{bad} TEST FILE(S) FAILED")
sys.exit(1 if bad else 0)
