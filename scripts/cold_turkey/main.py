import json
import sqlite3

DB_PATH = "/Library/Application Support/Cold Turkey/data-app.db"

def decode(s):
    data = s[5:]
    return ''.join(chr(int(data[i:i+2], 16) - 0x11) for i in range(0, len(data), 2))

def encode(s):
    return "CTB17" + ''.join(f'{ord(c) + 0x11:02X}' for c in s)

conn = sqlite3.connect(DB_PATH)
c = conn.cursor()
raw = c.execute("SELECT value FROM settings WHERE key = 'settings'").fetchone()[0]
dat = json.loads(decode(raw))
dat["additional"]["proStatus"] = "free" if dat["additional"]["proStatus"] == "pro" else "pro"
c.execute("UPDATE settings SET value = ? WHERE key = 'settings'", (encode(json.dumps(dat)),))
conn.commit()
conn.close()
print("Toggled to:", dat["additional"]["proStatus"])
