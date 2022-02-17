{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE UndecidableInstances #-}

module Control.Carrier.Storage.KeyValue where

import           Control.Algebra                        hiding (Handler)
import           Control.Carrier.Transaction.Cancel
import           Control.Effect.Exception
import           Control.Effect.Lift
import           Control.Effect.Reader
import           Control.Effect.Storage.KeyValue
import qualified Control.Effect.Storage.Single.KeyValue as S
import           Control.Monad.Catch                    (MonadCatch, MonadThrow)
import           Lens.Micro
import           PureMQ.Database
import           PureMQ.GlobalTransactions
import           PureMQ.Types
import           Unsafe.Coerce                          (unsafeCoerce)

newtype KeyValueStorageC m a = KeyValueStorageC
  { runKeyValueStorageC :: m a }
  deriving (Applicative, Functor, Monad, MonadThrow, MonadCatch)

instance
  ( Has (Lift IO) sig m
  , Has (Reader (Maybe TransactionID)) sig m
  , Has (Reader GTransactions) sig m
  , Algebra sig m )
  => Algebra (KeyValueStorage :+: sig) (KeyValueStorageC m) where
  alg hdl sig ctx = KeyValueStorageC handled
    where
      handled = case sig of
        L (Lookup db name key) -> fmap (<$ ctx) do
          keyValC <- getKeyValueStorageCarrier db name
          withTransaction db name $ \tId -> case keyValC of
            (StorageCarrier runC) -> sendIO $ runC tId $ S.lookup key
        L (Insert db name key val) -> fmap (<$ ctx) do
          keyValC <- getKeyValueStorageCarrier db name
          withTransaction db name $ \tId -> case keyValC of
            (StorageCarrier runC) -> sendIO $ runC tId $ S.insert key val
        L (Modify db name key f) -> fmap (<$ ctx) do
          keyValC <- getKeyValueStorageCarrier db name
          withTransaction db name $ \tId -> case keyValC of
            (StorageCarrier runC) -> sendIO $ runC tId $ S.modify key f
        L (Delete db (name :: StorageName k v) key) -> fmap (<$ ctx) do
          keyValC <- getKeyValueStorageCarrier db name
          withTransaction db name $ \tId -> case keyValC of
            (StorageCarrier runC) -> sendIO $ runC tId $ S.delete @k @v key
        R other      -> alg (runKeyValueStorageC . hdl) other ctx
        where
          withTransaction db name ma = do
            mGTransId <- ask
            gTranses <- ask
            mLTransId <- case mGTransId of
              Just tId ->
                sendIO $ lookupLocalTransactionId gTranses tId (db ^. #databaseId) name
              Nothing ->
                pure Nothing
            ma mLTransId
