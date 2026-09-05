"""Compatibility alias for shared parent runtime."""
import sys
from omarchy_parent.core import paths
sys.modules[__name__] = paths
