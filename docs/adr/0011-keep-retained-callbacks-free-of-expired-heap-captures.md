# Keep retained callbacks free of expired heap captures

Helix retains callbacks after engine reload; captured Steel heap cells can then
crash GC ([issue 10](https://github.com/ivoronin/grove.hx/issues/10)). Capturing a
local function binding can create such a cell without an explicit `box`.

Callbacks retained by Helix must not capture these cells, directly or
transitively. Move shared hook helpers and recurring timer functions to module
scope, passing dependencies explicitly. Immutable argument captures and
synchronous local helpers remain allowed. Verify with configuration reload tests.

Revisit when the supported runtime releases old callback roots before destroying
their heap and the GC regressions pass without this restriction.
