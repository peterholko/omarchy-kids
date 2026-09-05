"""Compatibility imports; the core hosts independent time and school services."""
from .service import Account, Service, DEMO_STATUS, TICK_SECONDS
from omarchy_parent.core.daemon import Daemon
from omarchy_parent.core.auth import parent_password_ok
from omarchy_parent.core import session
