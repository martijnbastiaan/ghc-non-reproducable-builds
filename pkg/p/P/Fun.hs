module P.Fun (fun) where

-- | An ordinary function (not a class method) without rules of its own. It
-- ignores its argument, so the argument gets no discount and is not strict.
fun :: Int -> Int
fun _ = 0
{-# OPAQUE fun #-}
