module P.Fun (fun) where

-- | An ordinary function (not a class method) without rules of its own.
fun :: Int -> Int
fun x = x
{-# OPAQUE fun #-}
