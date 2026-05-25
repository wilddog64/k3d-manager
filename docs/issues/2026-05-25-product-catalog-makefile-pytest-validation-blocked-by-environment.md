# Product Catalog Makefile pytest validation blocked by environment

## What I tested
- Updated `shopping-cart-product-catalog/Makefile` to replace bare `pytest` with `$(PYTHON) -m pytest` in test targets only.
- Ran `make test-unit` from `shopping-cart-product-catalog` without activating the venv.
- Tried a temporary venv-based validation path to provide `pytest` on PATH without changing the repo.

## Actual Output

### `make test-unit`
```text
[0;34mRunning unit tests...[0m 
python3 -m pytest tests/unit/ -v
/opt/homebrew/opt/python@3.14/bin/python3.14: No module named pytest
make: *** [test-unit] Error 1
```

### Temporary venv attempt
```text
WARNING: The directory '/Users/cliang/Library/Caches/pip' or its parent directory is not owned or is not writable by the current user. The cache has been disabled. Check the permissions and owner of that directory. If executing pip with sudo, you should use sudo's -H flag.
WARNING: Retrying (Retry(total=4, connect=None, read=None, redirect=None, status=None)) after connection broken by 'NameResolutionError("HTTPSConnection(host='pypi.org', port=443): Failed to resolve 'pypi.org' ([Errno 8] nodename nor servname provided, or not known)")': /simple/pytest/
WARNING: Retrying (Retry(total=3, connect=None, read=None, redirect=None, redirect=None)) after connection broken by 'NameResolutionError("HTTPSConnection(host='pypi.org', port=443): Failed to resolve 'pypi.org' ([Errno 8] nodename nor servname provided, or not known)")': /simple/pytest/
WARNING: Retrying (Retry(total=2, connect=None, read=None, redirect=None, redirect=None)) after connection broken by 'NameResolutionError("HTTPSConnection(host='pypi.org', port=443): Failed to resolve 'pypi.org' ([Errno 8] nodename nor servname provided, or not known)")': /simple/pytest/
WARNING: Retrying (Retry(total=1, connect=None, read=None, redirect=None, redirect=None)) after connection broken by 'NameResolutionError("HTTPSConnection(host='pypi.org', port=443): Failed to resolve 'pypi.org' ([Errno 8] nodename nor servname provided, or not known)")': /simple/pytest/
WARNING: Retrying (Retry(total=0, connect=None, read=None, redirect=None, redirect=None)) after connection broken by 'NameResolutionError("HTTPSConnection(host='pypi.org', port=443): Failed to resolve 'pypi.org' ([Errno 8] nodename nor servname provided, or not known)")': /simple/pytest/
ERROR: Could not find a version that satisfies the requirement pytest (from versions: none)
ERROR: No matching distribution found for pytest
```

## Root Cause
- The repo change is correct, but this machine’s system `python3` does not have `pytest` installed.
- Network access is unavailable here, so a temporary virtualenv cannot install `pytest` from PyPI for validation.

## Recommended Follow-up
- Re-run `make test-unit` in an environment where `pytest` is already installed for `python3`, or where the repo’s virtualenv can be populated from an accessible package mirror.
