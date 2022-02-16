{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module PureMQ.GlobalTransactions where

import           Control.Concurrent.MVar
import           Control.Effect.Transaction.Low as T
import           Control.Exception
import           Data.Coerce
import           Data.IORef
import           Data.Map.Strict                (Map)
import qualified Data.Map.Strict                as Map
import           Data.Maybe                     (fromMaybe)
import           Data.Typeable
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
  -> StorageName k v
  -> IO (Maybe TransactionID)
lookupLocalTransactionId gTranses tId dId name
  = handle (\(e :: GTransactionError) -> pure Nothing) do
    gTransesMap <- readMVar $ gTranses ^. #unGTransactions
    gTrans <- maybe (throwIO GTransactionIsNotFound) pure
      $ Map.lookup tId gTransesMap
    gTransMap <- readIORef $ gTrans ^. #unGTransaction
    gTransData <- maybe (throwIO LTransactionIsNotFound) pure
      $ Map.lookup (dId, coerce name) gTransMap
    pure $ Just $ gTransData ^. #localTransactionId

mkGTransactionData
  :: TransactionCarrier
  -> TransactionID
  -> GTransactionData
mkGTransactionData (TransactionCarrier _ runC) tId
  = GTransactionData
  { localTransactionId = tId
  , commitPrepare = runC $ T.commitPrepare tId
  , commit = runC $ T.commit tId
  , rollback = runC $ T.rollback tId }

insertLocalTransactionId
  :: (Typeable k, Typeable v)
  => GTransactions
  -> TransactionID -- global
  -> Database
  -> StorageName k v
  -> TransactionID -- local
  -> IO ()
insertLocalTransactionId gTranses gtId db name ltId = do
  gTransesMap <- readMVar $ gTranses ^. #unGTransactions
  gTrans <- maybe (throwIO GTransactionIsNotFound) pure
    $ Map.lookup gtId gTransesMap
  gTransMap <- readIORef $ gTrans ^. #unGTransaction
  transC <- getTransactionCarrier db name
  let gTransData = mkGTransactionData transC ltId
  atomicWriteIORef (gTrans ^. #unGTransaction)
    $! Map.insert (db ^. #databaseId, coerce name) gTransData gTransMap

getLocalTransactionId
  :: (Typeable k, Typeable v)
  => GTransactions
  -> TransactionID
  -> Maybe IsolationLevel
  -> Database
  -> StorageName k v
  -> IO TransactionID
getLocalTransactionId gTranses gtId mLvl db name = do
  gTransesMap <- readMVar $ gTranses ^. #unGTransactions
  gTrans <- maybe (throwIO GTransactionIsNotFound) pure
    $ Map.lookup gtId gTransesMap
  gTransMap <- readIORef $ gTrans ^. #unGTransaction
  let mTransData = Map.lookup (db ^. #databaseId, coerce name) gTransMap
  case mTransData of
    Just gTransData ->
      pure $ gTransData ^. #localTransactionId
    Nothing -> do
      transC <- getTransactionCarrier db name
      ltId <- initPrepare' transC
      let gTransData = mkGTransactionData transC ltId
      atomicWriteIORef (gTrans ^. #unGTransaction)
        $! Map.insert (db ^. #databaseId, coerce name) gTransData gTransMap
      pure ltId
  where
    initPrepare' (TransactionCarrier _ runC)
      = runC $ initPrepare (fromMaybe ReadCommitted mLvl)

commitAllPrepare
  :: GTransactions
  -> TransactionID
  -> IO ()
commitAllPrepare gTranses tId = do
  gTransesMap <- readMVar $ gTranses ^. #unGTransactions
  gTrans <- maybe (throwIO GTransactionIsNotFound) pure
    $ Map.lookup tId gTransesMap
  gTransMap <- readIORef $ gTrans ^. #unGTransaction
  let
    gTransDatas = Map.elems gTransMap
    commits = gTransDatas ^.. traversed . #commitPrepare
  sequence_ commits

commitAll
  :: GTransactions
  -> TransactionID
  -> IO ()
commitAll gTranses tId = do
  gTransesMap <- readMVar $ gTranses ^. #unGTransactions
  gTrans <- maybe (throwIO GTransactionIsNotFound) pure
    $ Map.lookup tId gTransesMap
  gTransMap <- readIORef $ gTrans ^. #unGTransaction
  let
    gTransDatas = Map.elems gTransMap
    commits = gTransDatas ^.. traversed . #commit
  sequence_ commits

rollbackAll
  :: GTransactions
  -> TransactionID
  -> IO ()
rollbackAll gTranses tId = do
  gTransesMap <- readMVar $ gTranses ^. #unGTransactions
  gTrans <- maybe (throwIO GTransactionIsNotFound) pure
    $ Map.lookup tId gTransesMap
  gTransMap <- readIORef $ gTrans ^. #unGTransaction
  let
    gTransDatas = Map.elems gTransMap
    rollbacks = gTransDatas ^.. traversed . #rollback
  sequence_ rollbacks
