"""
Rootdir conftest.

Its only job is to exist here: pytest prepends the directory containing the
rootdir conftest to `sys.path`, which is what makes `import summarize` resolve
when tests run from anywhere in the repo. Without it, pytest's default prepend
import mode only adds `backend/tests/` and the package is invisible.
"""
