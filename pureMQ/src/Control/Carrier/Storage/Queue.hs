{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE UndecidableInstances #-}

module Control.Carrier.Storage.Queue where

import           Control.Algebra                     hiding (Handler)
import           Control.Carrier.Transaction.Cancel
import           Control.Effect.Exception
import           Control.Effect.Lift
import           Control.Effect.Reader
import           Control.Effect.Storage.Queue
import qualified Control.Effect.Storage.Single.Queue as S
import           Control.Monad.Catch                 (MonadCatch, MonadThrow)
import           Lens.Micro
import           PureMQ.Database
import           PureMQ.GlobalTransactions
import           PureMQ.Types
import           Unsafe.Coerce                       (unsafeCoerce)

newtype QueueStorageC m a = QueueStorageC
  { runQueueStorageC :: m a }
  deriving (Applicative, Functor, Monad, MonadThrow, MonadCatch)

instance
  ( Has (Lift IO) sig m
  , Has (Reader (Maybe TransactionID)) sig m
  , Has (Reader GTransactions) sig m
  , Algebra sig m )
  => Algebra (QueueStorage :+: sig) (QueueStorageC m) where
  alg hdl sig ctx = QueueStorageC handled
    where
      handled = case sig of
        L (Push db name key) -> fmap (<$ ctx) do
          queueC <- getQueueStorageCarrier db name
          withTransaction db name $ \tId -> case queueC of
            (StorageCarrier runC) -> sendIO $ runC tId $ S.push key
        L (Pull db name) -> fmap (<$ ctx) do
          queueC <- getQueueStorageCarrier db name
          withTransaction db name $ \tId -> case queueC of
            (StorageCarrier runC) -> sendIO $ runC tId S.pull
        L (PullIfExist db name) -> fmap (<$ ctx) do
          queueC <- getQueueStorageCarrier db name
          withTransaction db name $ \tId -> case queueC of
            (StorageCarrier runC) -> sendIO $ runC tId S.pullIfExist
        L (Peek db name) -> fmap (<$ ctx) do
          queueC <- getQueueStorageCarrier db name
          withTransaction db name $ \tId -> case queueC of
            (StorageCarrier runC) -> sendIO $ runC tId S.peek
        L (PeekIfExist db name) -> fmap (<$ ctx) do
          queueC <- getQueueStorageCarrier db name
          withTransaction db name $ \tId -> case queueC of
            (StorageCarrier runC) -> sendIO $ runC tId S.peekIfExist
        R other      -> alg (runQueueStorageC . hdl) other ctx
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
