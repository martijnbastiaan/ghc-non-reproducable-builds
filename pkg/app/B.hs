-- | The module whose interface (and code) changes. It does not import A or
-- P.Rule. The unfolding of 'g' is either  fun (f x)  or  fun (h (h (h x))).
module B (f, g) where

import P.Fun (fun)

h :: Int -> Int
h = negate
{-# OPAQUE h #-}

-- Exported, and too big to be inlined unconditionally.
f :: Int -> Int
f x = h (h (h x))

g :: Int -> Int
g x = fun (f x)
