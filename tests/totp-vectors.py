#!/usr/bin/env python3
"""RFC 6238 test vectors for bin/otp — run before shipping a change.

    python3 tests/totp-vectors.py

Any failure here means every code the widget shows is wrong.
"""

import base64
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path

HELPER = Path(__file__).resolve().parent.parent / "bin" / "otp"
otp = SourceFileLoader("otp", str(HELPER)).load_module()


def b32(text):
    return base64.b32encode(text.encode()).decode()


# RFC 6238 §Appendix B: T=59 is the shared instant across all three hashes.
CASES = [
    ("SHA1", "12345678901234567890", 59, "94287082"),
    ("SHA1", "12345678901234567890", 1111111109, "07081804"),
    ("SHA1", "12345678901234567890", 2000000000, "69279037"),
    ("SHA256", "12345678901234567890123456789012", 59, "46119246"),
    ("SHA512", "1234567890123456789012345678901234567890123456789012345678901234", 59, "90693936"),
]

failures = 0
for algorithm, key, at, want in CASES:
    got = otp.totp(b32(key), digits=8, algorithm=algorithm, at=at)["code"]
    ok = got == want
    failures += 0 if ok else 1
    print(f"{algorithm:<6} T={at:<11} {got} want {want} {'ok' if ok else 'FAIL'}")

# Secrets pasted with spaces or in lower case must still work.
assert otp.normalize_secret("jbsw y3dp-ehpk3pxp") == "JBSWY3DPEHPK3PXP"
print("normalize ok")

sys.exit(1 if failures else 0)
