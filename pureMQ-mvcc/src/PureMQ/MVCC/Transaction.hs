module PureMQ.MVCC.Transaction where

import           Control.Applicative
import           Control.Concurrent
import           Control.Concurrent.MVar      (readMVar)
import           Control.Concurrent.STM.TChan
import           Control.Concurrent.STM.TVar
import           Control.Exception
import           Control.Monad
import           Control.Monad.STM
import           Data.Coerce
import           Data.Generics.Labels         ()
import           Data.IntMap                  (IntMap)
import qualified Data.IntMap                  as Map
import           Data.IntSet                  (IntSet)
import qualified Data.IntSet                  as Set
import           GHC.Generics
import           GHC.IORef
import           Lens.Micro
import           PureMQ.MVCC.Types
import           PureMQ.Types

initPrepare
  :: IsolationLevel
  -> MvccMap m v
  -> (WithModeGlobal m -> IO (WithModeLocal m))
  -> IO TransactionID
initPrepare isolationLevel MvccMap{..} mkLock = do
  CommittedTransactions{..} <- readTVarIO committed
  pullLock <- mkLock queueExtention
  let
    status = Initiated
    modifyLog = ModifyLog $! Map.empty
    deleteLog = DeleteLog $! Set.empty
    ranges
      | isolationLevel == ReadCommitted = []
      | isolationLevel == Serializable = filter (/= (Nothing, Nothing))
          [ ( fst <$> Map.lookupMin transactions -- A bit messy
            , nextKey >>= flip Map.lookupLT transactions <&> fst )
          , ( nextKey, fst <$> Map.lookupMax transactions ) ]
  transaction <- fmap Transaction $! newIORef $! TransactionData{..}
  insertInitiated transaction
  where
    insertInitiated trans = atomically do
      UncommittedTransactions{..} <- readTVar uncommitted
      writeTVar uncommitted
        $! UncommittedTransactions
            (mkNextKey nextKey)
            (Map.insert nextKey trans transactions)
      pure $ coerce nextKey
    mkNextKey k
      | k == maxBound = 0
      | otherwise = k + 1

initPrepareKeyValue
  :: IsolationLevel
  -> MvccMap KeyValue v
  -> IO TransactionID
initPrepareKeyValue lvl mvccMap
  = initPrepare lvl mvccMap $ const $ pure ()

initPrepareCombined
  :: IsolationLevel
  -> MvccMap Combined v
  -> IO TransactionID
initPrepareCombined lvl mvccMap
  = initPrepare lvl mvccMap
  $ \ext -> atomically
  $ dupTChan
  $ ext ^. #pullLock

commitPrepare :: TransactionID -> MvccMap m v -> IO ()
commitPrepare transId MvccMap{..} = do
  UncommittedTransactions{..} <- readTVarIO uncommitted
  ref <- maybe (throwIO $ TransactionWasNotFound transId) (pure . unTransaction)
    $ Map.lookup (coerce transId) transactions
  transData <- readIORef ref
  let currentStatus = transData ^. #status
  when (currentStatus /= Initiated)
    $ throwIO
    $ WrongTransStatusChange currentStatus Prepared
  writeIORef ref $! set #status Prepared transData

cancelPrepare :: TransactionID -> MvccMap m v -> IO ()
cancelPrepare transId MvccMap{..} = do
  UncommittedTransactions{..} <- readTVarIO uncommitted
  ref <- maybe (throwIO $ TransactionWasNotFound transId) (pure . unTransaction)
    $ Map.lookup (coerce transId) transactions
  transData <- readIORef ref
  let currentStatus = transData ^. #status
  when (currentStatus /= Committed)
    $ throwIO
    $ WrongTransStatusChange currentStatus Canceled
  writeIORef ref $! set #status Canceled transData

commitKeyValue :: TransactionID -> MvccMap KeyValue v -> IO ()
commitKeyValue transId MvccMap{..} = do
  UncommittedTransactions{..} <- readTVarIO uncommitted
  ref <- maybe (throwIO $ TransactionWasNotFound transId) (pure . unTransaction)
    $ Map.lookup (coerce transId) transactions
  transData <- readIORef ref
  let currentStatus = transData ^. #status
  when (currentStatus /= Prepared)
    $ throwIO
    $ WrongTransStatusChange currentStatus Committed
  atomically $ do
    modifyTVar' committed
      $ over #transactions (Map.insert (coerce transId) transData)
      . over #nextKey (updateIfNeed $ coerce transId)
    modifyTVar' uncommitted
      $ over #transactions $ Map.delete $ coerce transId
  where
    updateIfNeed n Nothing = Just n
    updateIfNeed _ x       = x

commitAsyncKeyValue :: TransactionID -> MvccMap KeyValue v -> IO ()
commitAsyncKeyValue transId MvccMap{..} = do
  UncommittedTransactions{..} <- readTVarIO uncommitted
  ref <- maybe (throwIO $ TransactionWasNotFound transId) (pure . unTransaction)
    $ Map.lookup (coerce transId) transactions
  transData <- readIORef ref
  let currentStatus = transData ^. #status
  when (currentStatus /= Prepared)
    $ throwIO
    $ WrongTransStatusChange currentStatus Committed
  void $ forkIO $ atomically $ do
    modifyTVar' committed
      $ over #transactions (Map.insert (coerce transId) (transData & #status .~ Committed))
      . over #nextKey (updateIfNeed $ coerce transId)
    modifyTVar' uncommitted
      $ over #transactions $ Map.delete $ coerce transId
  where
    updateIfNeed n Nothing = Just n
    updateIfNeed _ x       = x

commitCombined :: TransactionID -> MvccMap Combined v -> IO ()
commitCombined transId MvccMap{..} = do
  UncommittedTransactions{..} <- readTVarIO uncommitted
  ref <- maybe (throwIO $ TransactionWasNotFound transId) (pure . unTransaction)
    $ Map.lookup (coerce transId) transactions
  transData@TransactionData{..} <- readIORef ref
  let currentStatus = transData ^. #status
  when (currentStatus /= Prepared)
    $ throwIO
    $ WrongTransStatusChange currentStatus Committed
  atomically $ do
    modifyTVar' committed
      $ over #transactions (Map.insert (coerce transId) transData)
      . over #nextKey (updateIfNeed $ coerce transId)
    modifyTVar' uncommitted
      $ over #transactions $ Map.delete $ coerce transId
    when (Map.size (unModifyLog modifyLog) > 0)
      $ writeTChan (queueExtention ^. #pullLock) ()
  where
    updateIfNeed n Nothing = Just n
    updateIfNeed _ x       = x

commitAsyncCombined :: TransactionID -> MvccMap Combined v -> IO ()
commitAsyncCombined transId MvccMap{..} = do
  UncommittedTransactions{..} <- readTVarIO uncommitted
  ref <- maybe (throwIO $ TransactionWasNotFound transId) (pure . unTransaction)
    $ Map.lookup (coerce transId) transactions
  transData@TransactionData{..} <- readIORef ref
  let currentStatus = transData ^. #status
  when (currentStatus /= Prepared)
    $ throwIO
    $ WrongTransStatusChange currentStatus Committed
  void $ forkIO $ atomically $ do
    modifyTVar' committed
      $ over #transactions (Map.insert (coerce transId) (transData & #status .~ Committed))
      . over #nextKey (updateIfNeed $ coerce transId)
    modifyTVar' uncommitted
      $ over #transactions $ Map.delete $ coerce transId
    when (Map.size (unModifyLog modifyLog) > 0)
      $ writeTChan (queueExtention ^. #pullLock) ()
  where
    updateIfNeed n Nothing = Just n
    updateIfNeed _ x       = x

-- WARNING: Vacuum is not concurrent operation.
-- Only one thread shoud run vacuum for singular Map.
vacuum :: MvccMap m v -> IO ()
vacuum m@MvccMap{..} = do
  CommittedTransactions{..} <- readTVarIO committed
  case nextKey >>= \k -> (k,) <$> Map.lookup k transactions of
    Just (key, trans) -> do
      vacuumSingle trans
      let nextKey'
            =   (fst <$> Map.lookupGT key transactions)
            <|> (fst <$> Map.lookupMin transactions)
      atomically
        $ modifyTVar' committed
        $ over #transactions (Map.delete key)
        . set  #nextKey nextKey'
    Nothing -> pure ()
  where
    vacuumSingle TransactionData{..} = do
      primMap <- readIORef primaryMap
      let
        removeElems [] m     = m
        removeElems (k:ks) m = removeElems ks (Map.delete k m)
        withModifies = Map.union (unModifyLog modifyLog)
        withDeletes  = removeElems (Set.toList $ coerce deleteLog)
        updatedMap = withDeletes $! withModifies primMap
      writeIORef primaryMap updatedMap
