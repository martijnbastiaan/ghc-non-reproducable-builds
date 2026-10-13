-- | The module whose interface (and code) changes.
--
-- It does not import A or Z, and nothing here mentions bytestring.
module B (f, g) where

data T = T Int

-- No arguments are scrutinised, so 'eqT' gives no argument discounts.
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

-- Exported (so not inlined just because it is used once) and too big to be
-- inlined unconditionally.
f :: Int -> T
f x = h (k x)

-- The unfolding of 'g' is either  eqT (f x) g1  or  eqT (h (k x)) g1
g :: Int -> Bool
g x = f x == T 10
