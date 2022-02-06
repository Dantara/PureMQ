module Control.Effect.Storage.Queue where

import           Control.Algebra
import           Control.Effect.Reader
import           Data.Kind
import           PureMQ.Database
import           PureMQ.Types

data QueueStorage (m :: Type -> Type) r where
  Push
    :: Database
    -> StorageName k v
    -> v
    -> QueueStorage m ()

  Pull
    :: Database
    -> StorageName k v
    -> QueueStorage m v

  PullIfExist
    :: Database
    -> StorageName k v
    -> QueueStorage m (Maybe v)

  Peek
    :: Database
    -> StorageName k v
    -> QueueStorage m v

  PeekIfExist
    :: Database
    -> StorageName k v
    -> QueueStorage m (Maybe v)

instance StorageEff QueueStorage

push
  :: forall k v m sig
  .  Has QueueStorage sig m
  => Database -> StorageName k v -> v -> m ()
push db s v = send $ Push db s v

pull
  :: forall k v m sig
  .  Has QueueStorage sig m
  => Database -> StorageName k v -> m v
pull db s = send $ Pull db s

pullIfExist
  :: forall k v m sig
  .  Has QueueStorage sig m
  => Database -> StorageName k v -> m (Maybe v)
pullIfExist db s = send $ PullIfExist db s

peek
  :: forall k v m sig
  .  Has QueueStorage sig m
  => Database -> StorageName k v -> m v
peek db s = send $ Peek db s

peekIfExist
  :: forall k v m sig
  .  Has QueueStorage sig m
  => Database -> StorageName k v -> m (Maybe v)
peekIfExist db s = send $ PeekIfExist db s
