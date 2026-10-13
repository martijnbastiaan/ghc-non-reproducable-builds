-- | Unrelated to B. Its only purpose is to load the interface of
-- Data.ByteString.Lazy, which carries non-orphan RULES whose head is
-- GHC.Classes.== (e.g. "ByteString.Lazy N==/length -> compareLength/==EQ").
--
-- The name sorts before B, so --make -j1 compiles it first.
module A () where

import qualified Data.ByteString.Lazy ()
