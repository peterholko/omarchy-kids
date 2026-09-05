"""Compatibility alias for the shared client."""
import sys
from omarchy_parent.core import cli
sys.modules[__name__] = cli
