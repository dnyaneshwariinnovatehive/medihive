"""Application configuration redirect wrapper.

Maintains backward compatibility for 'from config import ...' imports.
Actual configurations are defined in app_config.py.
"""

from app_config import *  # noqa: F401, F403