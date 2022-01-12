{-# LANGUAGE AllowAmbiguousTypes #-}

module Control.Effect.Storage.KeyValue where

import           Control.Algebra
import           Control.Effect.Storage.Common
import           Data.Kind

data KeyValueStorage k v (m :: Type -> Type) r where
  Lookup :: k -> KeyValueStorage k v m (Maybe v)
  Insert :: k -> v -> KeyValueStorage k v m ()
  Modify :: k -> (v -> v) -> KeyValueStorage k v m ()
  Delete :: k -> KeyValueStorage k v m ()

instance StorageEff (KeyValueStorage k v)

lookup
  :: forall k v m sig
  .  Has (KeyValueStorage k v) sig m
  => k -> m (Maybe v)
lookup k = send $ Lookup k

insert
  :: forall k v m sig
  .  Has (KeyValueStorage k v) sig m
  => k -> v -> m ()
insert k v = send $ Insert k v

modify
  :: forall k v m sig
  .  Has (KeyValueStorage k v) sig m
  => k -> (v -> v) -> m ()
modify k f = send $ Modify k f

delete
  :: forall k v m sig
  .  Has (KeyValueStorage k v) sig m
  => k -> m ()
delete k = send $ Delete @_ @v k
