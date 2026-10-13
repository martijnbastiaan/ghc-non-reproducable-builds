# `--make` output depends on which unrelated modules loaded interfaces first

## Summary

With `-O`, the Core that GHC produces for a module, and so its object code and
the unfoldings in its `.hi` file, can depend on which interfaces *other,
unrelated* modules in the same `ghc --make` session loaded before it. In
particular, it depends on whether those interfaces contained a non-orphan
`RULE` whose head is a function that the current module calls, even if that
rule can never fire in the current module.

As a result, for the same sources and flags:

* `ghc -c` (one-shot) and `ghc --make -j1` can give different results;
* `ghc --make -j1` gives different results depending on which modules happen
  to be compiled earlier (for example, depending on the module names);
* `ghc --make -jN` gives different results from build to build, because
  the result depends on which modules finish first.

The mechanism (details below): rules loaded into the external package state
(EPS) are visible to every later module in the session, and the mere presence
of a rule for `fun` makes the simplifier treat the arguments of `fun` as an
interesting context (`RuleArgCtxt`), so it inlines more eagerly there. On GHC
≤ 9.12 there's a second effect for class methods: an extra rule with a larger
arity delays the built-in class-op rule until the arguments have been
simplified, also in `RuleArgCtxt`.

## Steps to reproduce

```
./repro.sh                      # uses ghc-9.12.4
GHC=ghc-9.14.1 ./repro.sh
```

The script needs only `ghc` and `ghc-pkg` (no cabal). It compiles two small
examples in several ways and prints the unfolding of `B.g` from
`ghc --show-iface`. Each build goes to a new directory under `out/`.

### Example 1: only `base` and `bytestring` (`boot/`)

```haskell
module B (f, g) where                -- doesn't import A or Z

data T = T Int

eqT :: T -> T -> Bool
eqT _ _ = True
{-# OPAQUE eqT #-}

instance Eq T where
  (==) = eqT

h :: Int -> T
h = T
{-# OPAQUE h #-}

k :: Int -> Int
k = negate
{-# OPAQUE k #-}

f :: Int -> T
f x = h (k x)

g :: Int -> Bool
g x = f x == T 10
```

```haskell
module A () where                    -- Z.hs is identical, apart from its name
import qualified Data.ByteString.Lazy ()
```

`Data.ByteString.Lazy` defines non-orphan rules whose head is
`GHC.Classes.==`, e.g. `"ByteString.Lazy N==/length -> compareLength/==EQ"`.
They mention `Data.ByteString.Lazy.length`, so they're not orphans and are
only seen once that interface has been loaded.

### Example 2: a rule on an ordinary function (`pkg/`)

This example uses a tiny external package `p`, which `repro.sh` builds and
registers in a private package db:

```haskell
module P.Fun (fun) where
fun :: Int -> Int
fun _ = 0
{-# OPAQUE fun #-}

module P.Rule (bar) where
import P.Fun (fun)
bar :: Int -> Int
bar x = x + 1
{-# NOINLINE bar #-}
{-# RULES "fun/bar" forall x. fun (bar x) = x #-}
```

```haskell
module A () where
import P.Rule ()

module B (f, g) where                -- doesn't import A or P.Rule
import P.Fun (fun)
h :: Int -> Int
h = negate
{-# OPAQUE h #-}
f :: Int -> Int
f x = h (h (h x))
g :: Int -> Int
g x = fun (f x)
```

## Expected behaviour

`B.hi` and `B.o` depend only on `B.hs`, its (transitive) imports and the
flags. They should be the same in every row below.

## Actual behaviour

Output of `./repro.sh` with GHC 9.12.4:

```
GHC 9.12.4, flags: -O

== 1. base + bytestring only (boot/)
   B does not import A or Z. A and Z only import Data.ByteString.Lazy.
  ghc -c B.hs  (one-shot)                      g = eqT (f x) g1
  ghc --make -j1 B                             g = eqT (f x) g1
  ghc --make -j1 A B  (A built first)          g = eqT (h (k x)) g1
  ghc --make -j1 B Z  (Z built after)          g = eqT (f x) g1
  ghc --make -j4 B Z  (in parallel)            g = eqT (h (k x)) g1

  diff of 'ghc --show-iface B.hi', one-shot vs. --make -j1 A B:
    108c108
    <               \ (x['GHC.Types.Many] :: GHC.Types.Int) -> eqT (f x) g1]
    ---
    >               \ (x['GHC.Types.Many] :: GHC.Types.Int) -> eqT (h (k x)) g1]

  ghc --make -j4 B Z, with N filler bindings added to B, 10 runs each
  (o = eqT (f x) g1, I = eqT (h (k x)) g1; timing-dependent):
    N=0   oooooIoooo
    N=5   oooooIoooo
    N=10  ooIIoooIoI
    N=15  IIIoIIooII
    N=20  IoIIIIIIoI
    N=30  IIIIooIIII

== 2. A rule on an ordinary function, from a small external package (pkg/)
   Package p: P.Fun defines fun, P.Rule defines RULE "fun/bar" fun (bar x) = x.
  ghc -c B.hs  (one-shot)                      g = P.Fun.fun (f x)
  ghc --make -j1 B                             g = P.Fun.fun (f x)
  ghc --make -j1 A B  (A built first)          g = P.Fun.fun (h (h (h x)))

  diff of 'ghc --show-iface B.hi', one-shot vs. --make -j1 A B:
    51c51
    <               \ (x['GHC.Types.Many] :: GHC.Types.Int) -> P.Fun.fun (f x)]
    ---
    >               \ (x['GHC.Types.Many] :: GHC.Types.Int) -> P.Fun.fun (h (h (h x)))]
```

The `-j1` rows are stable from run to run. `ghc --make -j4 B Z` (with `Z` as
the direct importer of `Data.ByteString.Lazy`) also gave the same result on
every run here, because `Z` always loads the interface before `B` reaches the
simplifier. The sweep at the end makes the two race: the same command on the
same sources gives both results. The exact `N` where that happens depends on
the machine and its load.

The difference isn't limited to unfoldings: the code for `g` itself differs
(`-ddump-simpl`), and you get it with just `-O`. Neither
`-fexpose-all-unfoldings` nor `-fno-worker-wrapper` is needed.

## Affected versions

| GHC    | Example 1 (`==` rule from bytestring) | Example 2 (rule on a plain function) |
|--------|---------------------------------------|---------------------------------------|
| 9.4.8  | affected                              | affected                              |
| 9.6.7  | affected                              | affected                              |
| 9.8.4  | affected                              | affected                              |
| 9.10.3 | affected                              | affected                              |
| 9.12.4 | affected                              | affected                              |
| 9.14.1 | not affected                          | affected                              |

Older versions weren't tested: the example uses `OPAQUE`, which needs
GHC ≥ 9.4. The relevant code is unchanged on `master` as of 2026-04-27
(`40564e8daa`), so master is probably affected too. I haven't built it.

## Mechanism

### Verified

With `-dinline-check f` on example 1 (GHC 9.12.4), the inliner's decision for
the call `f x` differs only in the call context:

```
ghc -c B.hs                         ghc --make A B
Considering inlining: f             Considering inlining: f
  arg infos [TrivArg]                 arg infos [TrivArg]
  interesting continuation BoringCtxt   interesting continuation RuleArgCtxt
  some_benefit False                  some_benefit True
  guidance IF_ARGS [0] 40 0           guidance IF_ARGS [0] 40 0
  ANSWER = NO                         ANSWER = YES
```

The same holds for example 2 on GHC 9.14.1 (`BoringCtxt` in one-shot,
`RuleArgCtxt` after `A` has loaded `P.Rule`). `-ddump-rule-firings` shows
that no rule from `A`'s dependencies fires in `B`.

### Inferred from the GHC source

* Non-orphan rules from external packages live in `eps_rule_base`, which is
  shared by all modules of a `--make` session (and by all threads with
  `-jN`). Note [External package rules] says the EPS rule base "is constantly
  being updated as new interfaces are loaded". `getRules` filters only
  *orphan* rules by visibility (`re_visible_orphs`). A non-orphan rule is
  visible to every module compiled after its interface was loaded, whether
  or not the module depends on it.
* `GHC.Core.Opt.Simplify.Utils.mkArgInfo` sets
  `ai_encl = fun_has_rules || contHasRules cont`, and `lazyArgContext` and
  `strictArgContext` turn `ai_encl` into `RuleArgCtxt`, so that inlining
  happens more eagerly in the arguments of a function that has rules.
  `fun_has_rules` is true for *any* rule for `fun`, including rules that
  can't match. So a rule that only becomes visible because of an unrelated
  module changes the inlining decisions in the arguments of `fun`. This is
  example 2, and it is still the case in 9.14.1 and on master.
* On GHC ≤ 9.12 there's an additional class-op effect, which is example 1.
  `mkRewriteCall` used `TryRules n_required rules` with
  `n_required = maximum (map ruleArity rules)`. With only the built-in class-op
  rule for `==` (arity 2: the type and the dictionary), the rules are tried as
  soon as the dictionary has been seen. `==` rewrites to `eqT` before the
  value arguments are simplified, and they are then simplified as arguments
  of `eqT`, which has no rules (`BoringCtxt`). After `Data.ByteString.Lazy` has
  been loaded, `==` also has the bytestring rules (arity 4). Then the rules are
  only tried after all four arguments have been simplified, and that happens
  while the function is still `==`, so in `RuleArgCtxt`.
* Commit 5eeb66450219aba5108c13a8612a30f43e3f6589 ("Re-jig the way that the
  Simplifier tries RULES", for #25170, in 9.14.1) fixed that second effect:
  class-op rules are now tried before the arguments are simplified
  (Note [tryRules: plan (BEFORE)]). Note [When to apply rewrite rules] states
  the goal: "ensure that adding a new, unrelated rule that never fires does
  not change the simplifier behaviour", and mentions the case where the rule
  "wasn't even transitively below the module being compiled". The
  `RuleArgCtxt` path via `ai_encl` still breaks that goal, as example 2 shows.

### Possible fixes (untested)

* Make non-orphan EPS rules visible only if their defining module is in the
  transitive dependency closure of the module being compiled, as is already
  done for orphans. Then `--make` would see the same rules as one-shot.
* Or let `fun_has_rules` / `contHasRules` ignore rules that can't match
  (for example by a rough match on the arguments). This alone wouldn't make
  rule *firing* independent of what other modules loaded, though.

## Why this matters

* **Reproducible builds.** Identical sources and flags give different `.o`
  and `.hi` files, depending on the build tool's scheduling. This affects
  `cabal build` and `stack build`, which use `--make` (and `-j` for modules),
  and build systems that mix one-shot and `--make` builds. A different `.hi`
  also means a different ABI hash, so downstream packages get recompiled
  needlessly, and binary caches miss.
* **Clash.** The Clash compiler turns the Core of exposed unfoldings (packages
  are compiled with `-fexpose-all-unfoldings`) into hardware descriptions. For
  `clash-prelude` built with GHC 9.12.4, the generated VHDL and Verilog
  depended on whether the library had been built with `-j1`, with `-j4`, or
  one-shot. Concretely:
  * `Clash.Sized.Internal.Unsigned` and `Signed`: whether `pack` is inlined
    into `testBit` depends on whether `Clash.Explicit.BlockRam.Internal`
    (which imports `Data.ByteString.Lazy`) was compiled before them. Cause:
    the `==` rules from `Data.ByteString.Lazy`.
  * `Clash.Explicit.Signal`: whether `clockGen` is inlined into
    `sampleWithReset` depends on whether
    `Clash.Annotations.BitRepresentation.Deriving` (which imports
    `Data.Containers.ListUtils`) finished first. Cause: the rules with head
    `Data.Foldable.foldr` in `Data.Containers.ListUtils`. This varies between
    `-j4` builds.

  Both causes were confirmed by adding a module that only contains the
  respective `import` to a `--make` build of the module's dependency closure.
  The clash-prelude also differs without `-fexpose-all-unfoldings`.
