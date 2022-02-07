module PureMQ.GlobalTransactions where

import           Control.Concurrent.MVar
import           Control.Exception
import           Data.IORef
import           Data.Map.Strict         (Map)
import qualified Data.Map.Strict         as Map
import           GHC.Generics
import           Lens.Micro
import           PureMQ.Database
import           PureMQ.Types

newtype GTransactions = GTransactions
  { unGTransactions :: MVar (Map TransactionID GTransaction) }
  deriving (Generic)

newtype GTransaction = GTransaction
  { unGTransaction :: IORef (Map (DatabaseId, StorageName') GTransactionData) }
  deriving (Generic)

data GTransactionData = GTransactionData
  { localTransactionId :: TransactionID
  , commitPrepare      :: IO ()
  , commit             :: IO ()
  , rollback           :: IO () }
  deriving (Generic)

data GTransactionError
  = GTransactionIsNotFound
  | LTransactionIsNotFound
  deriving (Eq, Ord, Show, Generic)

instance Exception GTransactionError

initGTransactions :: IO GTransactions
initGTransactions = GTransactions <$> newMVar Map.empty

initGTransaction :: GTransactions -> IO TransactionID
initGTransaction (GTransactions transesVar) = do
  gTransesMap <- takeMVar transesVar
  newGTrans <- GTransaction <$> newIORef Map.empty
  case Map.lookupMax gTransesMap of
    Just (k, _) -> do
      putMVar transesVar $! Map.insert (k + 1) newGTrans gTransesMap
      pure (k + 1)
    Nothing -> do
      putMVar transesVar $! Map.insert 0 newGTrans gTransesMap
      pure 0

lookupLocalTransactionId
  :: GTransactions
  -> TransactionID
  -> DatabaseId
  -> StorageName'
  -> IO (Maybe TransactionID)
lookupLocalTransactionId gTranses tId dId name
  = handle (\(e :: GTransactionError) -> pure Nothing) do
    gTransesMap <- readMVar $ gTranses ^. #unGTransactions
    gTrans <- maybe (throwIO GTransactionIsNotFound) pure
      $ Map.lookup tId gTransesMap
    gTransMap <- readIORef $ gTrans ^. #unGTransaction
    gTransData <- maybe (throwIO LTransactionIsNotFound) pure
      $ Map.lookup (dId, name) gTransMap
    pure $ Just $ gTransData ^. #localTransactionId
