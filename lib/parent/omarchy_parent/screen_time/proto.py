"""Compatibility alias for shared parent runtime."""
import sys
from omarchy_parent.core import proto
sys.modules[__name__] = proto
