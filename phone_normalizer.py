"""German phone-number normalizer: structured input -> canonical E.164.

Python twin of the PostgreSQL function ``normalize_phone_de_e164_v1``
(see ``sql/normalize_phone_de_e164_v1.sql``). Both implement the same rules
and are checked against one shared golden-vector file.

Scope: German numbers only. Austrian, Swiss and other international numbers
are recognised and reported as ``unsupported_country`` rather than rejected
as garbage. This is a normalizer, not a validator: it does not check whether
a number is assigned or reachable.

Public API
----------
normalize_phone_result(raw) -> PhoneNormalizationResult   strict, DB-shaped
normalize_phone(raw)        -> "+49..." | None           strict, canonical only
normalize_phone_loose(raw)  -> "+49..." | None           search inside free text
is_extension_only(raw)      -> bool                      "Durchwahl 12" etc.
starts_with_local_format(raw) -> bool                    "030 ..." style input

The last three helpers are Python-only and have no SQL counterpart.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

NORMALIZATION_VERSION = "de_e164_v1"

# Characters allowed in a structured phone field: ASCII digits, '+', ASCII
# whitespace and the separators ( ) . / -
# Kept ASCII-only on purpose so that Python and PostgreSQL agree regardless of
# locale (see README, "Parity").
_ALLOWED_STRUCTURED = re.compile(r"^[0-9+ \t\n\r\f\v()./\-]*$")
_NON_DIGIT_OR_PLUS = re.compile(r"[^0-9+]")
_ASCII_LETTER = re.compile(r"[A-Za-z]")

# "+49" plus at least 7 digits.
MIN_DIALABLE_LENGTH = 10

# German extensions (Durchwahl) are usually 1-4 digits.
EXTENSION_MAX_DIGITS = 4

# Free-text search for something that looks like a full German number.
_LOOSE_FULL_NUMBER = re.compile(r"(\+49|0049|0\d{2,4})[ \-]?\d{3,}[\d \-]*")


@dataclass(frozen=True)
class PhoneNormalizationResult:
    phone_canonical: str | None
    normalization_status: str  # valid_de | unsupported_country | invalid
    country_code: str | None
    normalization_reason: str
    normalization_version: str = NORMALIZATION_VERSION


def _result(status: str, reason: str, canonical: str | None = None,
            country_code: str | None = None) -> PhoneNormalizationResult:
    return PhoneNormalizationResult(
        phone_canonical=canonical,
        normalization_status=status,
        country_code=country_code,
        normalization_reason=reason,
    )


def _german(candidate: str, reason: str) -> PhoneNormalizationResult:
    if candidate.startswith("+490"):
        return _result("invalid", "trunk_zero_after_country_code", country_code="49")
    if len(candidate) < MIN_DIALABLE_LENGTH:
        return _result("invalid", "too_short_de", country_code="49")
    return _result("valid_de", reason, canonical=candidate, country_code="49")


def normalize_phone_result(raw: str | None) -> PhoneNormalizationResult:
    """Strict normalization of a structured phone field (same rules as SQL).

    Arbitrary text such as "Durchwahl 123" is rejected; use
    normalize_phone_loose() for free text.
    """
    raw_trim = (raw or "").strip(" \t\n\r\f\v")

    if raw_trim == "":
        return _result("invalid", "empty")
    if _ASCII_LETTER.search(raw_trim):
        return _result("invalid", "contains_letters")
    if not _ALLOWED_STRUCTURED.match(raw_trim):
        return _result("invalid", "unsupported_characters")
    if raw_trim.count("+") > 1 or ("+" in raw_trim and not raw_trim.startswith("+")):
        return _result("invalid", "malformed_plus")

    compact = _NON_DIGIT_OR_PLUS.sub("", raw_trim)
    if compact == "":
        return _result("invalid", "empty_after_cleanup")

    if compact.startswith("+49"):
        return _german(compact, "valid_de_international")
    if compact.startswith("0049"):
        return _german("+49" + compact[4:], "valid_de_international_access")
    if re.fullmatch(r"0[1-9][0-9]+", compact):
        return _german("+49" + compact[1:], "valid_de_local")

    if compact.startswith(("+43", "0043")):
        return _result("unsupported_country", "unsupported_country_at", country_code="43")
    if compact.startswith(("+41", "0041")):
        return _result("unsupported_country", "unsupported_country_ch", country_code="41")
    if re.fullmatch(r"\+[1-9][0-9]{5,}", compact) or re.fullmatch(r"00[1-9][0-9]{5,}", compact):
        return _result("unsupported_country", "unsupported_country_other")

    return _result("invalid", "unparseable")


def normalize_phone(raw: str | None) -> str | None:
    """Canonical "+49..." for a full German number, otherwise None."""
    return normalize_phone_result(raw).phone_canonical


def normalize_phone_loose(raw: str | None) -> str | None:
    """Find and normalize the first German-looking number inside free text."""
    if not raw or not raw.strip():
        return None
    match = _LOOSE_FULL_NUMBER.search(raw)
    return normalize_phone(match.group(0)) if match else None


def is_extension_only(raw: str | None) -> bool:
    """True for a short extension without a main number ("Durchwahl 42").

    Five or more digits without a full number are treated as a broken number,
    not as an extension.
    """
    if not raw or not raw.strip() or normalize_phone_loose(raw):
        return False
    digits = sum(1 for ch in raw if ch in "0123456789")
    return 0 < digits <= EXTENSION_MAX_DIGITS


def starts_with_local_format(raw: str | None) -> bool:
    """True if the input was written in national format ("030 ...") and is valid.

    Useful as a data-quality hint: the number had to be rewritten to +49.
    "0049 ..." counts as international, not local.
    """
    if not raw or not raw.strip():
        return False
    result = normalize_phone_result(raw)
    return result.normalization_reason == "valid_de_local"
