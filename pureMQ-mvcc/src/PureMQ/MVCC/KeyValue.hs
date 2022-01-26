module PureMQ.MVCC.KeyValue where

import           Control.Concurrent
import           Control.Concurrent.STM
import           Control.Concurrent.STM.TChan
import           Control.Concurrent.STM.TVar
import           Control.Exception
import           Control.Monad
import           Data.Coerce
import           Data.Generics.Labels         ()
import           Data.IntMap                  (IntMap)
import qualified Data.IntMap                  as Map
import           Data.IntSet                  (IntSet)
import qualified Data.IntSet                  as Set
import           Data.Maybe                   (fromMaybe)
import           GHC.Generics
import           GHC.IORef
import           Lens.Micro
import           PureMQ.MVCC.Types
import           PureMQ.Types

data WasDeleted = WasDeleted
  deriving (Eq,Show, Generic)

instance Exception WasDeleted

lookup :: Key -> TransactionID -> MvccMap m v -> IO (Maybe v)
lookup key transId MvccMap{..} = handle (\WasDeleted -> pure Nothing) do
  uncommitted' <- readTVarIO uncommitted
  ref <- maybe (throwIO $ TransactionWasNotFound transId) (pure . unTransaction)
    $ Map.lookup (coerce transId) $ uncommitted' ^. #transactions
  transData <- readIORef ref
  when (transData ^. #status /= Initiated)
    $ throwIO $ WrongTransStatus $ transData ^. #status
  CommittedTransactions{..} <- readTVarIO committed
  mResult <- case (transData ^. #isolationLevel, nextKey) of
    (ReadCommited, Just splitter) -> do
      let
        (youngTs, oldTs)
          = over both (fmap snd . Map.toDescList)
          $ Map.partitionWithKey (\k _ -> k < splitter) transactions
        transDataList = transData : youngTs <> oldTs
      transDatasLookup transDataList
    (ReadCommited, Nothing) ->
      singleTransDataLookup transData
    (Serializable, _) -> do
      let
        mkPredicate (mLow, mHigh)
          = \k _ -> maybe True (< k) mLow && maybe True (> k) mHigh
        transDataList
          = fmap snd
          $ foldMap (\r -> Map.toDescList $ Map.filterWithKey (mkPredicate r) transactions)
          $ transData ^. #ranges
      transDatasLookup $ transData : transDataList
  maybe (Map.lookup (coerce key) <$> readIORef primaryMap) (pure . Just) mResult
  where
    transDatasLookup [] = pure Nothing
    transDatasLookup (t:ts) = do
      mResult <- singleTransDataLookup t
      maybe (transDatasLookup ts) (pure . Just) mResult
    singleTransDataLookup TransactionData{..} = do
      when (Set.member (coerce key) (coerce deleteLog))
        $ throwIO WasDeleted
      pure $ Map.lookup (coerce key) (unModifyLog modifyLog)

insert :: Key -> v -> TransactionID -> MvccMap m v -> IO ()
insert k v transId MvccMap{..} = do
  UncommittedTransactions{..} <- readTVarIO uncommitted
  ref <- maybe (throwIO $ TransactionWasNotFound transId) (pure . unTransaction)
    $ Map.lookup (coerce transId) transactions
  transData@TransactionData{..} <- readIORef ref
  when (status /= Initiated)
    $ throwIO $ WrongTransStatus status
  let updated = coerce $ Map.insert (coerce k) v (coerce modifyLog)
  writeIORef ref $! set #modifyLog updated transData

modify :: Key -> (v -> v) -> TransactionID -> MvccMap m v -> IO ()
modify k f transId MvccMap{..} = do
  UncommittedTransactions{..} <- readTVarIO uncommitted
  ref <- maybe (throwIO $ TransactionWasNotFound transId) (pure . unTransaction)
    $ Map.lookup (coerce transId) transactions
  transData@TransactionData{..} <- readIORef ref
  when (status /= Initiated)
    $ throwIO $ WrongTransStatus status
  let updated = coerce $ Map.adjust f (coerce k) (coerce modifyLog)
  writeIORef ref $! set #modifyLog updated transData

delete :: Key -> TransactionID -> MvccMap m v -> IO ()
delete k transId MvccMap{..} = do
  UncommittedTransactions{..} <- readTVarIO uncommitted
  ref <- maybe (throwIO $ TransactionWasNotFound transId) (pure . unTransaction)
    $ Map.lookup (coerce transId) transactions
  transData@TransactionData{..} <- readIORef ref
  when (status /= Initiated)
    $ throwIO $ WrongTransStatus status
  let
    deleteLog = coerce $ Set.insert (coerce k) (coerce deleteLog)
    modifyLog = coerce $ Map.delete (coerce k) (unModifyLog modifyLog)
  writeIORef ref $! set #deleteLog deleteLog transData
  writeIORef ref $! set #modifyLog modifyLog transData
