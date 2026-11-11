import json
import unittest
from pathlib import Path

from phone_normalizer import (
    NORMALIZATION_VERSION,
    is_extension_only,
    normalize_phone,
    normalize_phone_loose,
    normalize_phone_result,
    starts_with_local_format,
)

VECTORS = Path(__file__).with_name("golden_vectors.de_e164_v1.json")


def load_vectors() -> list[dict]:
    return json.loads(VECTORS.read_text(encoding="utf-8"))


class GoldenVectorTest(unittest.TestCase):
    def test_vectors_match_contract(self) -> None:
        for v in load_vectors():
            with self.subTest(v["label"]):
                r = normalize_phone_result(v["raw_phone"])
                self.assertEqual(r.phone_canonical, v["expected_canonical"])
                self.assertEqual(r.normalization_status, v["expected_status"])
                self.assertEqual(r.country_code, v["expected_country_code"])
                self.assertEqual(r.normalization_reason, v["expected_reason"])
                self.assertEqual(r.normalization_version, NORMALIZATION_VERSION)
                self.assertEqual(normalize_phone(v["raw_phone"]), v["expected_canonical"])

    def test_canonical_output_is_a_fixed_point(self) -> None:
        for v in load_vectors():
            if v["expected_status"] != "valid_de":
                continue
            with self.subTest(v["label"]):
                again = normalize_phone_result(v["expected_canonical"])
                self.assertEqual(again.phone_canonical, v["expected_canonical"])
                self.assertEqual(again.normalization_status, "valid_de")

    def test_vector_labels_are_unique(self) -> None:
        labels = [v["label"] for v in load_vectors()]
        self.assertEqual(len(labels), len(set(labels)))


class PythonOnlyHelpersTest(unittest.TestCase):
    def test_strict_mode_rejects_text_loose_mode_finds_number(self) -> None:
        text = "Bitte unter 030 23125 020 zurückrufen"
        self.assertIsNone(normalize_phone(text))
        self.assertEqual(normalize_phone_loose(text), "+493023125020")

    def test_loose_mode_without_number(self) -> None:
        self.assertIsNone(normalize_phone_loose("keine Angabe"))
        self.assertIsNone(normalize_phone_loose(""))
        self.assertIsNone(normalize_phone_loose(None))

    def test_extension_detection(self) -> None:
        self.assertTrue(is_extension_only("Durchwahl 42"))
        self.assertTrue(is_extension_only("123"))
        self.assertFalse(is_extension_only("Durchwahl 12345"))   # broken number, not an extension
        self.assertFalse(is_extension_only("+49 30 23125 021"))  # full number
        self.assertFalse(is_extension_only("keine Angabe"))
        self.assertFalse(is_extension_only(""))

    def test_local_format_hint(self) -> None:
        self.assertTrue(starts_with_local_format("030 23125 022"))
        self.assertFalse(starts_with_local_format("0049 30 23125 022"))
        self.assertFalse(starts_with_local_format("+49 30 23125 022"))
        self.assertFalse(starts_with_local_format("Bitte 030 23125 022 anrufen"))


if __name__ == "__main__":
    unittest.main()
