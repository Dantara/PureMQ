module Control.Effect.Storage.KeyValue where

import           Control.Algebra
import           Data.Kind
import           PureMQ.Types

data KeyValueStorage (m :: Type -> Type) r where
  Lookup
    :: Database
    -> StorageName k v
    -> k
    -> KeyValueStorage m (Maybe v)

  Insert
    :: Database
    -> StorageName k v
    -> k
    -> v
    -> KeyValueStorage m ()

  Modify
    :: Database
    -> StorageName k v
    -> k
    -> (v -> v)
    -> KeyValueStorage m ()

  Delete
    :: Database
    -> StorageName k v
    -> k
    -> KeyValueStorage m ()

instance StorageEff KeyValueStorage

lookup
  :: forall k v m sig
  .  Has KeyValueStorage sig m
  => Database -> StorageName k v -> k -> m (Maybe v)
lookup db s k = send $ Lookup db s k

insert
  :: forall k v m sig
  .  Has KeyValueStorage sig m
  => Database -> StorageName k v -> k -> v -> m ()
insert db s k v = send $ Insert db s k v

modify
  :: forall k v m sig
  .  Has KeyValueStorage sig m
  => Database -> StorageName k v -> k -> (v -> v) -> m ()
modify db s k f = send $ Modify db s k f

delete
  :: forall k v m sig
  .  Has KeyValueStorage sig m
  => Database -> StorageName k v -> k -> m ()
delete db s k = send $ Delete db s k
