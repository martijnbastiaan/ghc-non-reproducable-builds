# Minimization notes

## 1. clash-prelude outside cabal (`clash-prelude-repro/`)

* `flags.txt` is cabal's GHC command line minus the paths, with
  `-dynamic-too` kept: Template Haskell needs `.dyn_o` in one-shot mode.
  `order.txt` is the `-j1` compile order, used for one-shot builds (including
  the four `[boot]` modules).
  `run.sh N` does N `-j1` and N `-j4` builds and one one-shot build, and
  compares the normalised `--show-iface` output.
* Results (GHC 9.12.4): `-j1` is stable. One-shot differs from `-j1` in
  `Unsigned`/`Signed` (the `$fBitPackUnsigned2` call in `testBit`).
  `-j4` differs from `-j1` in `Clash.Explicit.Signal` and `Clash.Signal`
  (`clockGen` vs. `tbClockGen ... clockGen1`), and sometimes also in `Signed`
  or `Unsigned`. A full `--make` build takes about 1 minute; one-shot takes
  about 7 minutes.
* One-shot recompilation of `Unsigned.hs` against the `.hi` files of a `-j1`
  build gives the one-shot form. So the input interfaces are the same, and
  the difference comes from in-memory session state.
* `--make -fforce-recomp Unsigned.hs` (only its 32-module dependency closure)
  gives the one-shot form. Adding each of the 21 modules that `-j1` compiles
  before `Unsigned` but outside its closure, one at a time:
  only `Clash.Explicit.BlockRam.Internal` flips it. A module with only
  BlockRam.Internal's imports flips it too. Bisecting the imports:
  only `import qualified Data.ByteString.Lazy` matters.
* A `-dverbose-core2core` diff: the desugarer output is identical, and the
  first divergence is in the gentle simplifier run before `Specialise`.
  `-ddump-inlinings` shows `Stop[RuleArgCtxt]` instead of
  `BoringCtxt`/`DiscArgCtxt` in `testBit`, and an extra
  `Inlining done: $cpack`. `-ddump-rule-firings` doesn't change. The
  rules responsible are the `GHC.Classes.==`/`compare`/... rules in the
  interface of `Data.ByteString.Lazy`.
* `Clash.Explicit.Signal`: a diff of the inlinings between a `-j1` and a
  `-j4` build shows `clockGen` inlined in `RuleArgCtxt` under
  `Data.Foldable.foldr` (from the inlined `sample`) only in the `-j4` build.
  `Data.Containers.ListUtils` (containers) has non-orphan rules with head
  `Foldable.foldr`, and is imported by
  `Clash.Annotations.BitRepresentation.Deriving`, which `-j1` compiles after
  `Explicit.Signal`. Confirmed: adding a dummy module with only
  `import Data.Containers.ListUtils ()` flips `Explicit.Signal`.
* With `-fno-expose-all-unfoldings`, the `Unsigned` interface still differs
  (in the unfoldings that are still exposed).

## 2. Building the standalone example

* An orphan `SPECIALISE` rule (for `powImpl`) from a home module, compiled
  earlier but not imported, did **not** change anything: home-package rules
  are filtered to the dependencies. The leak is only through the EPS (rules
  from external packages).
* To get a difference, the function `f` that gets inlined must:
  * be exported, otherwise it is pre-inlined when it occurs once;
  * not be tiny (`UnfWhen`), otherwise it is inlined in any context;
  * be called as a lazy argument of a consumer without argument discounts.
    A consumer that scrutinises its argument gives `DiscArgCtxt`, and a strict
    one gives `RhsCtxt`, and both of those inline anyway. So `eqT _ _ = True`,
    and `fun _ = 0`, both `OPAQUE`.
* `-fexpose-all-unfoldings` and `-fno-worker-wrapper` aren't needed: `-O` is
  enough, on every version tested.
* `-jN` race: when `Z` imports `Data.ByteString.Lazy` directly, `Z` always
  wins the race (the interface is loaded at rename time), so `-j4 B Z` is
  stable here but different from `-j1 B Z`. Inserting an empty module
  `S` (`Z` imports `S`) and adding about 10–20 filler bindings to `B` makes
  the race visible: both outcomes over 10 runs. This depends on the machine
  and its load.
* GHC 9.14.1: example 1 no longer reproduces. A `polymorphic ==` variant
  (unknown dictionary) didn't help either: class methods always have their
  built-in class-op rule, so their arguments are always `RuleArgCtxt`. Also,
  `round`/`truncate` have no rules on 9.14 that load lazily. A boot-package
  rule on a non-method function that is loaded lazily wasn't found:
  `realToFrac`, `foldr`, `map` and `unpackCString#` already have rules in modules that
  are always loaded. Hence the tiny package `p` for example 2.
* GHC 9.2.8 isn't usable as-is: there is no `OPAQUE`, so `eqT` is inlined.

## Source pointers (GHC master checkout `~/code/ghc`, 40564e8daa)

* `GHC.Core.Opt.Simplify.Utils.mkArgInfo`: `ai_encl = fun_has_rules || contHasRules cont`
* `lazyArgContext` / `strictArgContext`: `encl_rules -> RuleArgCtxt`
* `GHC.Core.Rules.getRules`: only orphans are filtered by `re_visible_orphs`
* 9.12: `mkRewriteCall`, `n_required = maximum (map ruleArity rules)`
* Fix for the class-op effect: 5eeb66450219aba5108c13a8612a30f43e3f6589 (#25170), in 9.14.1
