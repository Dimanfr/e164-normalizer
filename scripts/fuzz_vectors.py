"""Generate random phone-like inputs and the Python normalizer's answers.

The output has the same shape as tests/golden_vectors.de_e164_v1.json, so
sql/golden_vectors_check.sql can replay it against PostgreSQL. If every row
passes, SQL and Python agree on these inputs.

    python3 scripts/fuzz_vectors.py --count 5000 --seed 1 > /tmp/fuzz.json

Generated numbers are random and may match real subscriber numbers. They are
written to stdout only for the check; do not commit or publish the output.
"""

from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from phone_normalizer import normalize_phone_result  # noqa: E402

PREFIXES = ["", "+49", "0049", "0", "+43", "0043", "+41", "0041", "+1", "001", "00", "+", "+490", "++49"]
# Letters used in escape sequences (b f n r t v x) are included on purpose:
# a mistyped escape in SQL or Python turns into one of them.
ALPHABET = (list("0123456789") * 6 + list(" -/.()+") + list("bfnrtvxaZ")
            + ["\t", "\n", "\r", "\f", "\v", "\u00a0", "\u00e4", "#", "*", "\u0663"])


def clean_input(rng: random.Random) -> str:
    """Mostly well-formed German input: prefix + digit groups + separators."""
    prefix = rng.choice(["+49", "+49 ", "0049 ", "0", "(0", "+490", "0049 0"])
    groups = [str(rng.randint(1, 9))] + ["".join(rng.choice("0123456789") for _ in range(rng.randint(1, 5)))
                                         for _ in range(rng.randint(1, 4))]
    sep = rng.choice([" ", "-", "/", ".", ") ", ""])
    return prefix + sep.join(groups)


def random_input(rng: random.Random) -> str:
    if rng.random() < 0.5:
        return clean_input(rng)
    body = "".join(rng.choice(ALPHABET) for _ in range(rng.randint(0, 16)))
    pad = rng.choice(["", " ", "  ", "\t", "\v", "\f", "v"])
    return pad + rng.choice(PREFIXES) + body + rng.choice(["", " ", "\n", "\v", "\r", "v"])


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=2000)
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    vectors = []
    for i in range(args.count):
        raw = random_input(rng)
        r = normalize_phone_result(raw)
        vectors.append({
            "label": f"fuzz_{i:05d}",
            "raw_phone": raw,
            "expected_status": r.normalization_status,
            "expected_canonical": r.phone_canonical,
            "expected_country_code": r.country_code,
            "expected_reason": r.normalization_reason,
        })
    json.dump(vectors, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
