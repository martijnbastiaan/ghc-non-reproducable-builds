module P.Rule (bar) where

import P.Fun (fun)

bar :: Int -> Int
bar x = x + 1
{-# NOINLINE bar #-}

-- | Not an orphan (it mentions 'bar' from this module), so GHC only sees it
-- once this interface has been loaded. Its head is 'fun' from P.Fun.
{-# RULES "fun/bar" forall x. fun (bar x) = x #-}
