{-# LANGUAGE ScopedTypeVariables #-}

module PureMQ.Database where

import           Control.Algebra
import           Control.Effect.Exception
import           Control.Effect.Lift
import           Control.Effect.Storage.Single.KeyValue
import           Control.Effect.Storage.Single.Queue
import           Control.Effect.Transaction.Low         (Transaction)
import qualified Control.Effect.Transaction.Low         as T
import           Control.Exception                      (Exception (..))
import           Data.Coerce
import           Data.Function                          (on)
import           Data.Generics.Labels                   ()
import           Data.Kind
import           Data.Map.Strict                        (Map)
import qualified Data.Map.Strict                        as Map
import           Data.Maybe
import           Data.Text                              (Text)
import           Data.Typeable                          (eqT)
import           GHC.Exception
import           GHC.Generics
import           Lens.Micro
import           PureMQ.Types
import           Type.Reflection
import           Unsafe.Coerce                          (unsafeCoerce)

data Database = Database
  { databaseId :: DatabaseId
  , storages   :: Map StorageName' Storage }
  deriving (Generic)

instance Eq Database where
  (==) = (==) `on` databaseId

newtype DatabaseId = DatabaseId
  { unwrapDatabaseId :: Word }
  deriving (Eq, Ord, Show, Generic)

newtype StorageName (k :: Type) (v :: Type) = StorageName
  { unwrapStorageName :: Text }
  deriving (Eq, Ord, Show, Generic)

newtype StorageName' = StorageName'
  { unwrapStorageName' :: Text }
  deriving (Eq, Ord, Show, Generic)

data Storage where
  Storage
    :: (Typeable k, Typeable v)
    => Carriers k v
    -> Storage

data Carriers k v = StorageCarriers
  { keyValCarrier :: Maybe (StorageCarrier (KeyValueStorage k v))
  , queueCarrier  :: Maybe (StorageCarrier (QueueStorage v))
  , transCarrier  :: TransactionCarrier }
  deriving (Generic)

data StorageCarrier t where
  StorageCarrier
    :: Has t sig m
    => (forall a . Maybe TransactionID -> m a -> IO a)
    -> StorageCarrier t

data TransactionCarrier where
  TransactionCarrier
    :: Has Transaction sig m
    => (forall a . m a -> IO a)
    -> TransactionCarrier

data DatabaseException
  = StorageIsNotFound
  | StorageTypesAreWrong
  | KeyValueStorageIsNotSupported
  | QueueStorageIsNotSupported
  deriving (Eq, Ord, Show, Generic)

instance Exception DatabaseException

getKeyValueStorageCarrier
  :: forall k v a m sig
  . ( Typeable k
    , Typeable v
    , Has (Lift IO) sig m )
  => Database
  -> StorageName k v
  -> m (StorageCarrier (KeyValueStorage k v))
getKeyValueStorageCarrier db name = do
  storage <- maybe (throwIO StorageIsNotFound) pure
    $ Map.lookup (coerce name)
    $ db ^. #storages
  carriers <- getCarriers storage
  maybe (throwIO KeyValueStorageIsNotSupported) pure
    $ carriers ^. #keyValCarrier
  where
    getCarriers :: Storage -> m (Carriers k v)
    getCarriers (Storage (carriers :: Carriers k' v'))
      = case (eqT @k @k', eqT @v @v') of
          (Just Refl, Just Refl) -> pure carriers
          (_, _)                 -> throwIO StorageTypesAreWrong

getQueueStorageCarrier
  :: forall k v m sig
  . ( Typeable k
    , Typeable v
    , Has (Lift IO) sig m )
  => Database
  -> StorageName k v
  -> m (StorageCarrier (QueueStorage v))
getQueueStorageCarrier db name = do
  storage <- maybe (throwIO StorageIsNotFound) pure
    $ Map.lookup (coerce name)
    $ db ^. #storages
  mQueueC <- mGetQueueCarrier storage
  maybe (throwIO QueueStorageIsNotSupported) pure mQueueC
  where
    mGetQueueCarrier :: Storage -> m (Maybe (StorageCarrier (QueueStorage v)))
    mGetQueueCarrier storage@(Storage (carriers :: Carriers k' v'))
      = case (eqT @k @k', eqT @k @NoKey, eqT @v @v') of
          (Just Refl, _, Just Refl) -> pure $ carriers ^. #queueCarrier
          (_, Just Refl, Just Refl) -> pure $ carriers ^. #queueCarrier
          (_, _, _)                 -> throwIO StorageTypesAreWrong

getTransactionCarrier
  :: forall k v a m sig
  . ( Typeable k
    , Typeable v
    , Has (Lift IO) sig m)
  => Database
  -> StorageName k v
  -> m TransactionCarrier
getTransactionCarrier db name = do
  storage <- maybe (throwIO StorageIsNotFound) pure
    $ Map.lookup (coerce name)
    $ db ^. #storages
  getCarrier storage
  where
    getCarrier :: Storage -> m TransactionCarrier
    getCarrier (Storage (carriers :: Carriers k' v'))
      = case (eqT @k @k', eqT @k @NoKey, eqT @v @v') of
          (Just Refl, _, Just Refl) -> pure $ carriers ^. #transCarrier
          (_, Just Refl, Just Refl) -> pure $ carriers ^. #transCarrier
          (_, _, _)                 -> throwIO StorageTypesAreWrong
