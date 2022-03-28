module PureMQ.MVCC.Queue where

import           Control.Concurrent
import           Control.Concurrent.MVar      (readMVar)
import           Control.Concurrent.STM
import           Control.Concurrent.STM.TChan
import           Control.Concurrent.STM.TVar
import           Control.Exception
import           Control.Monad
import           Data.Coerce
import           Data.Foldable
import           Data.Generics.Labels         ()
import           Data.IntMap                  (IntMap)
import qualified Data.IntMap                  as Map
import           Data.IntSet                  (IntSet)
import qualified Data.IntSet                  as Set
import           GHC.Generics
import           GHC.IORef
import           Lens.Micro
import           PureMQ.MVCC.KeyValue         (delete)
import           PureMQ.MVCC.Types
import           PureMQ.Types

push
  :: v
  -> TransactionID
  -> MvccMap CombinedM v
  -> IO ()
push val transId MvccMap{..} = do
  UncommittedTransactions{..} <- readTVarIO uncommitted
  ref <- maybe (throwIO $ TransactionWasNotFound transId) (pure . unTransaction)
    $ Map.lookup (coerce transId) transactions
  transData@TransactionData{..} <- readIORef ref
  when (status /= Initiated)
    $ throwIO $ WrongTransStatus status
  key <- coerce $ takeMVar $ queueExtention ^. #nextKey
  let updated = coerce $ Map.insert key val (coerce modifyLog)
  writeIORef ref $! set #modifyLog updated transData


peekIfExistWithKey
  :: TransactionID
  -> MvccMap CombinedM v
  -> IO (Maybe (Key, v))
peekIfExistWithKey transId MvccMap{..} = do
  uncommitted' <- readTVarIO uncommitted
  ref <- maybe (throwIO $ TransactionWasNotFound transId) (pure . unTransaction)
    $ Map.lookup (coerce transId) $ uncommitted' ^. #transactions
  transData <- readIORef ref
  when (transData ^. #status /= Initiated)
    $ throwIO $ WrongTransStatus $ transData ^. #status
  CommittedTransactions{..} <- readTVarIO committed
  let (mMin, deleted)
        = foldr singleTransDataPeek (Nothing, Set.empty)
        $ case (transData ^. #isolationLevel, nextKey) of
            (ReadCommitted, Just splitter) ->
              let (youngTs, oldTs)
                    = over both (fmap snd . Map.toDescList)
                    $ Map.partitionWithKey (\k _ -> k < splitter) transactions
              in transData : youngTs <> oldTs
            (ReadCommitted, Nothing) -> [transData]
            (Serializable, _) -> do
              let mkPredicate (mLow, mHigh)
                    = \k _ -> maybe True (< k) mLow && maybe True (> k) mHigh
              fmap snd
                $ foldMap (\r -> Map.toDescList $ Map.filterWithKey (mkPredicate r) transactions)
                $ transData ^. #ranges
  primMap <- readIORef primaryMap
  let updPrimMap = removeElems (Set.toList deleted) primMap
  pure $ coerce $ case (mMin, Map.lookupMin updPrimMap) of
    (Just (minK, minV), Just (pMinK, pMinV))
      | pMinK < minK -> Just (pMinK, pMinV)
      | otherwise -> Just (minK, minV)
    (Just mins, Nothing) -> Just mins
    (Nothing, Just mins) -> Just mins
    (Nothing, Nothing) -> Nothing
  where
    singleTransDataPeek TransactionData{..} (mMins, deletedSet) =
      let
        transMin = Map.lookupMin $ unModifyLog modifyLog
        updDeleted = maybe deletedSet (flip Set.insert deletedSet . fst)
          $ Set.minView (coerce deleteLog)
      in case (mMins, transMin) of
        (Just (currMinK, currMinV), Just (minK, minV))
          | minK < currMinK && Set.notMember minK deletedSet ->
            (Just (minK, minV), updDeleted)
          | otherwise ->
            (Just (currMinK, currMinV), updDeleted)
        (Just (currMinK, currMinV), Nothing) ->
          (Just (currMinK, currMinV), updDeleted)
        (Nothing, Just (minV, minK)) ->
          (Just (minV, minK), updDeleted)
        (Nothing, Nothing) ->
          (Nothing, updDeleted)
    removeElems [] m     = m
    removeElems (k:ks) m = removeElems ks (Map.delete k m)

peekIfExist
  :: TransactionID
  -> MvccMap CombinedM v
  -> IO (Maybe v)
peekIfExist = (fmap (fmap snd) .) . peekIfExistWithKey

pullIfExist
  :: TransactionID
  -> MvccMap CombinedM v
  -> IO (Maybe v)
pullIfExist transId mvccMap@MvccMap{..} = do
  mRes <- peekIfExistWithKey transId mvccMap
  maybe (pure Nothing) (\(k, v) -> delete k transId mvccMap >> pure (Just v)) mRes

withHead
  :: (TransactionID -> MvccMap CombinedM v -> IO (Maybe v))
  -> (TChan () -> IO ())
  -> TransactionID
  -> MvccMap CombinedM v
  -> IO v
withHead process lock transId mvccMap@MvccMap{..} = do
  UncommittedTransactions{..} <- readTVarIO uncommitted
  ref <- maybe (throwIO $ TransactionWasNotFound transId) (pure . unTransaction)
    $ Map.lookup (coerce transId) transactions
  transData <- readIORef ref
  mElm <- process transId mvccMap
  case (mElm, transData ^. #isolationLevel) of
    (Just elm, _) ->
      pure elm
    (Nothing, ReadCommitted) -> do
      lock $ transData ^. #pullLock
      withHead process lock transId mvccMap
    (Nothing, Serializable) ->
      throwIO $ NotSupportedOperationOnLevel $ transData ^. #isolationLevel

peek
  :: TransactionID
  -> MvccMap CombinedM v
  -> IO v
peek = withHead peekIfExist (atomically . peekTChan)

pull
  :: TransactionID
  -> MvccMap CombinedM v
  -> IO v
pull = withHead pullIfExist (atomically . readTChan)
