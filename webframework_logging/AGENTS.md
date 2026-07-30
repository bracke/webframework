# Agent instructions — webframework_logging

Bridge exposing the logging library as webframework's diagnostics logger; its behaviour is exercised by the webframework test suite. Part of the webframework workspace.

This workspace enforces GNAT 15 through Alire (`gnat_native = "=15.2.1"` in
every manifest). Do not run plain system GNAT / GPRBuild / GNATprove / GNATdoc
from `PATH`; use Alire-selected tools — `alr exec -- gnatls --version` must
report `GNATLS 15.x`.

Build this crate:

```sh
alr build
```
