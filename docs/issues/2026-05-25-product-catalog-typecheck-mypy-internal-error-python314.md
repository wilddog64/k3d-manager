# Product catalog `make typecheck` hits mypy internal error on local Python 3.14 venv

## What I tested
- Ran `make typecheck` in `shopping-cart-product-catalog` after wiring the Makefile to use `.venv/bin/mypy`.

## Actual Output
```text
[0;34mRunning type checker...[0m 
.venv/bin/mypy src/
error: INTERNAL ERROR -- Please try using mypy master on GitHub:
https://mypy.readthedocs.io/en/stable/common_issues.html#using-a-development-mypy-build
If this issue continues with mypy master, please report a bug at https://github.com/python/mypy/issues
version: 2.1.0
note: please use --show-traceback to print a traceback when reporting a bug
make: *** [typecheck] Error 2
```

## Notes
- This was observed in the local Python 3.14 venv created for validation on this machine.
- The CI workflow in this task uses Python 3.11, so this appears environment-specific rather than a code regression from the task.
