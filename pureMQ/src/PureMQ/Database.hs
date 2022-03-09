{-# LANGUAGE ScopedTypeVariables #-}

module PureMQ.Database where

import           Control.Algebra
import           Control.Concurrent.MVar
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
import           Data.String                            (IsString)
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
  , storages   :: MVar Storages }
  deriving (Generic)

instance Eq Database where
  (==) = (==) `on` databaseId

newtype DatabaseId = DatabaseId
  { unwrapDatabaseId :: Word }
  deriving (Eq, Ord, Show, Generic, Num)

newtype StorageName (k :: Type) (v :: Type) = StorageName
  { unwrapStorageName :: Text }
  deriving (Eq, Ord, Show, Generic, IsString)

newtype StorageName' = StorageName'
  { unwrapStorageName' :: Text }
  deriving (Eq, Ord, Show, Generic, IsString)

newtype Storages = Storages
  { unwrapStorages :: Map StorageName' Storage }
  deriving (Generic)

data Storage where
  Storage
    :: (Typeable k, Typeable v)
    => Carriers k v
    -> Storage

data Carriers k v = Carriers
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
  | StorageAlreadyExists
  | StorageTypesAreWrong
  | KeyValueStorageIsNotSupported
  | QueueStorageIsNotSupported
  deriving (Eq, Ord, Show, Generic)

instance Exception DatabaseException

newDatabase :: Has (Lift IO) sig m => DatabaseId -> m Database
newDatabase databaseId = do
  storages <- sendIO $ newMVar $ Storages Map.empty
  pure Database{..}

addStorage
  :: Has (Lift IO) sig m
  => StorageName k v
  -> Storage
  -> Database
  -> m ()
addStorage name store db = do
  storages <- sendIO $ takeMVar $ db ^. #storages
  let mStorage = Map.lookup (coerce name) (unwrapStorages storages)
  case mStorage of
    Just _ -> do
      sendIO $ putMVar (db ^. #storages) storages
      throwIO StorageAlreadyExists
    Nothing ->
      sendIO
        $ putMVar (db ^. #storages)
        $ Storages
        $ Map.insert (coerce name) store (coerce storages)

removeStorage
  :: Has (Lift IO) sig m
  => StorageName k v
  -> Database
  -> m ()
removeStorage name db = do
  storages <- sendIO $ takeMVar $ db ^. #storages
  let mStorage = Map.lookup (coerce name) (unwrapStorages storages)
  case mStorage of
    Just _ ->
      sendIO
        $ putMVar (db ^. #storages)
        $ Storages
        $ Map.delete (coerce name) (coerce storages)
    Nothing -> do
      sendIO $ putMVar (db ^. #storages) storages
      throwIO StorageIsNotFound

getKeyValueStorageCarrier
  :: forall k v a m sig
  . ( Typeable k
    , Typeable v
    , Has (Lift IO) sig m )
  => Database
  -> StorageName k v
  -> m (StorageCarrier (KeyValueStorage k v))
getKeyValueStorageCarrier db name = do
  storages <- sendIO $ readMVar $ db ^. #storages
  storage <- maybe (throwIO StorageIsNotFound) pure
    $ Map.lookup (coerce name)
    $ unwrapStorages storages
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
  storages <- sendIO $ readMVar $ db ^. #storages
  storage <- maybe (throwIO StorageIsNotFound) pure
    $ Map.lookup (coerce name)
    $ unwrapStorages storages
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
  storages <- sendIO $ readMVar $ db ^. #storages
  storage <- maybe (throwIO StorageIsNotFound) pure
    $ Map.lookup (coerce name)
    $ unwrapStorages storages
  getCarrier storage
  where
    getCarrier :: Storage -> m TransactionCarrier
    getCarrier (Storage (carriers :: Carriers k' v'))
      = case (eqT @k @k', eqT @k @NoKey, eqT @v @v') of
          (Just Refl, _, Just Refl) -> pure $ carriers ^. #transCarrier
          (_, Just Refl, Just Refl) -> pure $ carriers ^. #transCarrier
          (_, _, _)                 -> throwIO StorageTypesAreWrong

newtype DBCounter = DBCounter
  { unDBCounter :: MVar DatabaseId }
  deriving Generic

initDBCounter :: Has (Lift IO) sig m => m DBCounter
initDBCounter = fmap DBCounter $ sendIO $ newMVar 0

nextDatabaseId :: Has (Lift IO) sig m => DBCounter -> m DatabaseId
nextDatabaseId (DBCounter var) = do
  id' <- sendIO $ takeMVar var
  sendIO $ putMVar var $ id' + 1
  pure id'
