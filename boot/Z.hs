-- | Unrelated to B. Its only purpose is to load the interface of
-- Data.ByteString.Lazy, which carries non-orphan RULES whose head is
-- GHC.Classes.== (e.g. "ByteString.Lazy N==/length -> compareLength/==EQ").
--
-- Identical to A, but the name sorts after B, so --make -j1 compiles it after B.
module Z () where

import qualified Data.ByteString.Lazy ()
