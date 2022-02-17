module Control.Effect.Storage.Queue where

import           Control.Algebra
import           Control.Effect.Reader
import           Data.Kind
import           Data.Typeable
import           PureMQ.Database
import           PureMQ.Types

data QueueStorage (m :: Type -> Type) r where
  Push
    :: (Typeable k, Typeable v)
    => Database
    -> StorageName k v
    -> v
    -> QueueStorage m ()

  Pull
    :: (Typeable k, Typeable v)
    => Database
    -> StorageName k v
    -> QueueStorage m v

  PullIfExist
    :: (Typeable k, Typeable v)
    => Database
    -> StorageName k v
    -> QueueStorage m (Maybe v)

  Peek
    :: (Typeable k, Typeable v)
    => Database
    -> StorageName k v
    -> QueueStorage m v

  PeekIfExist
    :: (Typeable k, Typeable v)
    => Database
    -> StorageName k v
    -> QueueStorage m (Maybe v)

instance StorageEff QueueStorage

push
  :: forall k v m sig
  .  ( Typeable k, Typeable v
     , Has QueueStorage sig m )
  => Database -> StorageName k v -> v -> m ()
push db s v = send $ Push db s v

pull
  :: forall k v m sig
  .  ( Typeable k, Typeable v
     , Has QueueStorage sig m )
  => Database -> StorageName k v -> m v
pull db s = send $ Pull db s

pullIfExist
  :: forall k v m sig
  .  ( Typeable k, Typeable v
     , Has QueueStorage sig m )
  => Database -> StorageName k v -> m (Maybe v)
pullIfExist db s = send $ PullIfExist db s

peek
  :: forall k v m sig
  .  ( Typeable k, Typeable v
     , Has QueueStorage sig m )
  => Database -> StorageName k v -> m v
peek db s = send $ Peek db s

peekIfExist
  :: forall k v m sig
  .  ( Typeable k, Typeable v
     , Has QueueStorage sig m )
  => Database -> StorageName k v -> m (Maybe v)
peekIfExist db s = send $ PeekIfExist db s
