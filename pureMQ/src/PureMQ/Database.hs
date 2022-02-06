module PureMQ.Database where

import           Control.Algebra
import           Control.Effect.Exception
import           Control.Effect.Lift
import           Control.Effect.Storage.Single.KeyValue
import           Control.Effect.Storage.Single.Queue
import           Control.Effect.Transaction.Low         (Transaction)
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
  | CannotCastResultValue
  deriving (Eq, Ord, Show, Generic)

instance Exception DatabaseException

runStorageCarrier
  :: Has t sig m
  => StorageCarrier t
  -> Maybe TransactionID
  -> m a
  -> IO a
runStorageCarrier (StorageCarrier f) tid ma
  = f tid $ unsafeCoerce ma -- I hope it will work

runTransactionCarrier
  :: Has Transaction sig m
  => TransactionCarrier
  -> m a
  -> IO a
runTransactionCarrier (TransactionCarrier f) ma
  = f $ unsafeCoerce ma

runKeyValueStorage
  :: forall k v a m t sigM sigT
  . ( Typeable k
    , Typeable v
    , Has (Lift IO) sigM m
    , Has (KeyValueStorage k v) sigT t )
  => Database
  -> StorageName k v
  -> Maybe TransactionID
  -> t a
  -> m a
runKeyValueStorage db name tid action = do
  storage <- maybe (throwIO StorageIsNotFound) pure
    $ Map.lookup (coerce name)
    $ db ^. #storages
  carriers <- getCarriers storage
  keyValC <- maybe (throwIO KeyValueStorageIsNotSupported) pure
    $ carriers ^. #keyValCarrier
  sendIO $ runStorageCarrier keyValC tid action
  where
    getCarriers :: Storage -> m (Carriers k v)
    getCarriers (Storage (carriers :: Carriers k' v'))
      = case (eqT @k @k', eqT @v @v') of
          (Just Refl, Just Refl) -> pure carriers
          (_, _)                 -> throwIO StorageTypesAreWrong

runQueueStorage
  :: forall k v a m t sigM sigT
  . ( Typeable k
    , Typeable v
    , Has (Lift IO) sigM m
    , Has (QueueStorage v) sigT t )
  => Database
  -> StorageName k v
  -> Maybe TransactionID
  -> t a
  -> m a
runQueueStorage db name tid action = do
  storage <- maybe (throwIO StorageIsNotFound) pure
    $ Map.lookup (coerce name)
    $ db ^. #storages
  mQueueC <- mGetQueueCarrier storage
  queueC <- maybe (throwIO QueueStorageIsNotSupported) pure mQueueC
  sendIO $ runStorageCarrier queueC tid action
  where
    mGetQueueCarrier :: Storage -> m (Maybe (StorageCarrier (QueueStorage v)))
    mGetQueueCarrier (Storage (carriers :: Carriers k' v'))
      = case (eqT @k @k', eqT @k @NoKey, eqT @v @v') of
          (Just Refl, _, Just Refl) -> pure $ carriers ^. #queueCarrier
          (_, Just Refl, Just Refl) -> pure $ carriers ^. #queueCarrier
          (_, _, _)                 -> throwIO StorageTypesAreWrong

runTransaction
  :: forall k v a m t sigM sigT
  . ( Typeable k
    , Typeable v
    , Has (Lift IO) sigM m
    , Has Transaction sigT t )
  => Database
  -> StorageName k v
  -> t a
  -> m a
runTransaction db name action = do
  storage <- maybe (throwIO StorageIsNotFound) pure
    $ Map.lookup (coerce name)
    $ db ^. #storages
  transC <- getTransactionC storage
  sendIO $ runTransactionCarrier transC action
  where
    getTransactionC :: Storage -> m TransactionCarrier
    getTransactionC (Storage (carriers :: Carriers k' v'))
      = case (eqT @k @k', eqT @k @NoKey, eqT @v @v') of
          (Just Refl, _, Just Refl) -> pure $ carriers ^. #transCarrier
          (_, Just Refl, Just Refl) -> pure $ carriers ^. #transCarrier
          (_, _, _)                 -> throwIO StorageTypesAreWrong
