"""Compatibility alias for shared parent runtime."""
import sys
from omarchy_parent.core import clock
sys.modules[__name__] = clock
