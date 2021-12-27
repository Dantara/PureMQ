module PureMQ.MVCC.Transaction where

import           Control.Concurrent
import           Control.Concurrent.MVar (readMVar)
import           Control.Monad
import           Data.Coerce
import           Data.Generics.Labels    ()
import           Data.IntMap             (IntMap)
import qualified Data.IntMap             as Map
import           Data.IntSet             (IntSet)
import qualified Data.IntSet             as Set
import           Data.Sequence           (Seq (..), ViewR (..), (<|), (|>))
import qualified Data.Sequence           as Seq
import           GHC.Generics
import           GHC.IORef
import           Lens.Micro
import           PureMQ.MVCC.Types
import           PureMQ.Types

initPrepare :: MvccMap m v -> IO (Transaction v)
initPrepare MvccMap{..} = do
  let
    status = Initiated
    modifyLog = ModifyLog $! Map.empty
    deleteLog = DeleteLog $! Set.empty
  fmap Transaction $ newIORef $! TransactionData{..}

commitPrepare :: Transaction v -> IO (Maybe TransactionError)
commitPrepare trans@(Transaction ref) = do
  transData <- readIORef ref
  let currentStatus = transData ^. #status
  case currentStatus of
    Initiated -> do
      writeIORef ref $! set #status Prepared transData
      pure Nothing
    _ ->
      pure $ Just $ WrongTransStatusChange currentStatus Prepared

cancelPrepare :: Transaction v -> IO (Maybe TransactionError)
cancelPrepare trans@(Transaction ref) = do
  transData <- readIORef ref
  let currentStatus = transData ^. #status
  case currentStatus of
    Committed ->
      pure $ Just $ WrongTransStatusChange currentStatus Canceled
    _ -> do
      writeIORef ref $! set #status Canceled transData
      pure Nothing

commit :: Transaction v -> MvccMap m v -> IO (Maybe TransactionError)
commit trans@(Transaction ref) MvccMap{..} = do
  transData <- readIORef ref
  let currentStatus = transData ^. #status
  case currentStatus of
    Prepared -> do
      writeIORef ref $! set #status Committed transData
      modifyMVar_ transactionsQueue (\seq -> pure $! seq |> trans)
      pure Nothing
    _ ->
      pure $ Just $ WrongTransStatusChange currentStatus Committed

commitAsync :: Transaction v -> MvccMap m v -> IO (Maybe TransactionError)
commitAsync trans@(Transaction ref) MvccMap{..} = do
  transData <- readIORef ref
  let currentStatus = transData ^. #status
  case currentStatus of
    Prepared -> do
      writeIORef ref $! set #status Committed transData
      void
        $ forkIO
        $ modifyMVar_ transactionsQueue (\seq -> pure $! seq |> trans)
      pure Nothing
    _ ->
      pure $ Just $ WrongTransStatusChange currentStatus Committed

vacuum :: MvccMap m v -> IO ()
vacuum m@MvccMap{..} = do
  currentSeq <- readMVar transactionsQueue
  needToRemove <- case Seq.viewr currentSeq of
    EmptyR   -> pure False
    _ :> elm -> vacuumSingle elm >> pure True
  when needToRemove do
    modifyMVar_ transactionsQueue (pure . Seq.deleteAt 0)
    vacuum m
  where
    vacuumSingle (Transaction ref) = do
      TransactionData{..} <- readIORef ref
      case status of
        Committed -> do
          primMap <- readIORef primaryMap
          let
            removeElems [] m     = m
            removeElems (k:ks) m = removeElems ks (Map.delete k m)
            withModifies = Map.union (unModifyLog modifyLog)
            withDeletes  = removeElems (Set.toList $ coerce deleteLog)
            updatedMap = withDeletes $! withModifies primMap
          writeIORef primaryMap updatedMap
        _ -> pure ()
