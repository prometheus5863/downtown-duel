"""Zips the Web export for itch.io: export/web/* at the zip's top level (index.html first), into
   export/downtown-duel-web.zip. Refuses an export whose pack looks unfinished.
   Run after exporting:  python tools/make_itch_zip.py ."""
import os, sys, zipfile
P = sys.argv[1] if len(sys.argv) > 1 else "."
SRC = os.path.join(P, "export", "web")
OUT = os.path.join(P, "export", "downtown-duel-web.zip")
pck = os.path.join(SRC, "index.pck")
if not os.path.exists(os.path.join(SRC, "index.html")) or not os.path.exists(pck):
    sys.exit("no export in export/web: run the Web export first")
if os.path.getsize(pck) < 20 * 2**20:
    sys.exit(f"index.pck is only {os.path.getsize(pck) / 2**20:.1f} MB: the export looks unfinished")
names = sorted(os.listdir(SRC), key=lambda n: (n != "index.html", n))
with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for n in names:
        z.write(os.path.join(SRC, n), n)
print(f"ok: {OUT}  {os.path.getsize(OUT) / 2**20:.1f} MB, {len(names)} files")
