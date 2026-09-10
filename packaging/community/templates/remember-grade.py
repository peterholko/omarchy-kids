"""Remember the grade selected in Math Time, in its own user state file."""
import os
from pathlib import Path
import sys

grade = int(sys.argv[1])
if not 1 <= grade <= 7:
    raise SystemExit('grade must be between 1 and 7')
directory = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'omarchy-math-time'
directory.mkdir(parents=True, exist_ok=True)
(directory / 'grade').write_text(str(grade) + '\n')
