#!/usr/bin/env bash
# Install the SQL function into a database and check it against the golden
# vectors, a random parity sample, and the example table.
#
#   DATABASE_URL=postgres://user@host:5432/db scripts/check_sql.sh
#
# Use a scratch database: the script creates public.normalize_phone_de_e164_v1
# and public.demo_contacts there.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${DATABASE_URL:?set DATABASE_URL to a scratch PostgreSQL database}"
PSQL=(psql "$DATABASE_URL" -X -q -v ON_ERROR_STOP=1)

"${PSQL[@]}" -f sql/normalize_phone_de_e164_v1.sql
"${PSQL[@]}" -v vectors_file=tests/golden_vectors.de_e164_v1.json -f sql/golden_vectors_check.sql

fuzz="$(mktemp)"
trap 'rm -f "$fuzz"' EXIT
python3 scripts/fuzz_vectors.py --count "${FUZZ_COUNT:-3000}" --seed "${FUZZ_SEED:-1}" > "$fuzz"
"${PSQL[@]}" -v vectors_file="$fuzz" -f sql/golden_vectors_check.sql

"${PSQL[@]}" -f sql/example_contacts_unique_by_e164.sql
"${PSQL[@]}" -f sql/example_contacts_unique_by_e164_check.sql
echo "SQL checks passed"
