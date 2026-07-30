# Agent instructions — stack_check

Builds and tests the web-stack slice in dependency order (integration gate). Part of the webframework workspace.

This workspace enforces GNAT 15 through Alire (`gnat_native = "=15.2.1"` in
every manifest). Do not run plain system GNAT / GPRBuild / GNATprove / GNATdoc
from `PATH`; use Alire-selected tools — `alr exec -- gnatls --version` must
report `GNATLS 15.x`.

Build and run this crate:

```sh
alr build && ./bin/stack_check
```
