import os
import sys
import unittest

# Ensure backend package is importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

# Determine if PostgreSQL is available for integration tests
PG_TEST_URL = os.environ.get(
    'TEST_DATABASE_URL',
    '',  # Default: no PostgreSQL, tests are skipped
)

PG_AVAILABLE = bool(PG_TEST_URL)


def requires_pg(test_func):
    """Decorator to skip a test when PostgreSQL is not available."""
    return unittest.skipUnless(PG_AVAILABLE, "PostgreSQL not available (set TEST_DATABASE_URL)")(test_func)
