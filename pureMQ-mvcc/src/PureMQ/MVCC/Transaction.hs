module PureMQ.MVCC.Transaction where

import           Control.Applicative
import           Control.Concurrent
import           Control.Concurrent.MVar     (readMVar)
import           Control.Concurrent.STM.TVar
import           Control.Exception
import           Control.Monad
import           Control.Monad.STM
import           Data.Coerce
import           Data.Generics.Labels        ()
import           Data.IntMap                 (IntMap)
import qualified Data.IntMap                 as Map
import           Data.IntSet                 (IntSet)
import qualified Data.IntSet                 as Set
import           Data.Sequence               (Seq (..), ViewR (..), (<|), (|>))
import qualified Data.Sequence               as Seq
import           GHC.Generics
import           GHC.IORef
import           Lens.Micro
import           PureMQ.MVCC.Types
import           PureMQ.Types

initPrepare :: IsolationLevel -> MvccMap m v -> IO TransactionID
initPrepare isolationLevel MvccMap{..} = do
  CommittedTransactions{..} <- readTVarIO committed
  let
    status = Initiated
    modifyLog = ModifyLog $! Map.empty
    deleteLog = DeleteLog $! Set.empty
    ranges
      | isolationLevel == ReadCommited = []
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

commitKeyValue :: TransactionID -> MvccMap m v -> IO ()
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

commitAsyncKeyValue :: TransactionID -> MvccMap m v -> IO ()
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

-- commitCombined :: Transaction v -> MvccMap Combined v -> IO ()
-- commitCombined trans@(Transaction ref) MvccMap{..} = do
--   transData@TransactionData{..} <- readIORef ref
--   let
--     currentStatus = transData ^. #status
--     sizeDiff = Map.size (unModifyLog modifyLog) - Set.size (coerce deleteLog)
--   case currentStatus of
--     Prepared -> do
--       writeIORef ref $! set #status Committed transData
--       when (sizeDiff < 0)
--         $ replicateM_ (negate sizeDiff)
--         $ forkIO
--         $ writeChan (queueExtention ^. #pullLock) ()
--       modifyMVar_ transactionsQueue (\seq -> pure $! seq |> trans)
--       when (sizeDiff > 0)
--         $ replicateM_ sizeDiff
--         $ writeChan (queueExtention ^. #pullLock) ()
--       pure Nothing
--     _ ->
--       pure $ Just $ WrongTransStatusChange currentStatus Committed

-- commitAsyncCombined :: Transaction v -> MvccMap Combined v -> IO ()
-- commitAsyncCombined trans@(Transaction ref) MvccMap{..} = do
--   transData@TransactionData{..} <- readIORef ref
--   let
--     currentStatus = transData ^. #status
--     sizeDiff = Map.size (unModifyLog modifyLog) - Set.size (coerce deleteLog)
--   case currentStatus of
--     Prepared -> do
--       writeIORef ref $! set #status Committed transData
--       when (sizeDiff < 0)
--         $ replicateM_ (negate sizeDiff)
--         $ forkIO
--         $ writeChan (queueExtention ^. #pullLock) ()
--       void
--         $ forkIO
--         $ modifyMVar_ transactionsQueue (\seq -> pure $! seq |> trans)
--       when (sizeDiff > 0)
--         $ void
--         $ forkIO
--         $ replicateM_ sizeDiff
--         $ writeChan (queueExtention ^. #pullLock) ()
--       pure Nothing
--     _ ->
--       pure $ Just $ WrongTransStatusChange currentStatus Committed

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
