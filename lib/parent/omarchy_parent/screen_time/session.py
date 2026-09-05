"""Compatibility alias for shared parent runtime."""
import sys
from omarchy_parent.core import session
sys.modules[__name__] = session
