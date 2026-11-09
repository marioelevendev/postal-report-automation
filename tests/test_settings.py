"""Unit tests for environment flag parsing."""

import os
import unittest
from unittest.mock import patch

from main import _read_boolean


class ReadBooleanTests(unittest.TestCase):
    """Check friendly values used by POSTAL_COPY_TO_TALEND."""

    def test_true_and_false_values(self) -> None:
        """Common operational values are accepted case-insensitively."""

        with patch.dict(os.environ, {"FLAG": "YeS"}):
            self.assertTrue(_read_boolean("FLAG", default=False))
        with patch.dict(os.environ, {"FLAG": "off"}):
            self.assertFalse(_read_boolean("FLAG", default=True))

    def test_missing_value_uses_default(self) -> None:
        """An absent flag uses the declared default."""

        with patch.dict(os.environ, {}, clear=False):
            os.environ.pop("MISSING_POSTAL_FLAG", None)
            self.assertTrue(_read_boolean("MISSING_POSTAL_FLAG", default=True))

    def test_invalid_value_fails_clearly(self) -> None:
        """A typo must not silently enable or disable network delivery."""

        with patch.dict(os.environ, {"FLAG": "sometimes"}):
            with self.assertRaisesRegex(RuntimeError, "must be true/false"):
                _read_boolean("FLAG", default=False)


if __name__ == "__main__":
    unittest.main()

