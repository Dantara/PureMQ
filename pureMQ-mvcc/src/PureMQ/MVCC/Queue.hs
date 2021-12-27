module PureMQ.MVCC.Queue where

import           Control.Concurrent
import           Control.Concurrent.MVar (readMVar)
import           Control.Exception
import           Control.Monad
import           Data.Coerce
import           Data.Foldable
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
import           PureMQ.MVCC.KeyValue    (delete)
import           PureMQ.MVCC.Types
import           PureMQ.Types

push
  :: v
  -> Transaction v
  -> MvccMap Combined v
  -> IO (Maybe TransactionError)
push v (Transaction ref) MvccMap{..} = do
  td@TransactionData{..} <- readIORef ref
  case status of
    Initiated -> do
      key <- coerce $ takeMVar $ queueExtention ^. #nextKey
      let updated = coerce $ Map.insert key v (coerce modifyLog)
      writeIORef ref $! set #modifyLog updated td
      pure Nothing
    status ->
      pure $ Just $ WrongTransStatus status

peekIfExistWithKey
  :: Maybe (Transaction v)
  -> MvccMap Combined v
  -> IO (Maybe (Key, v))
peekIfExistWithKey mTrans MvccMap{..} = do
  committed <- readMVar transactionsQueue
  let transactions = maybe committed (committed |>) mTrans
  (mbMin, deleted) <- foldrM singleTransPeek (Nothing, Set.empty) transactions
  primMap <- readIORef primaryMap
  let updPrimMap = removeElems (Set.toList deleted) primMap
  pure $ coerce $ case (mbMin, Map.lookupMin updPrimMap) of
    (Just (minK, minV), Just (pMinK, pMinV))
      | pMinK < minK -> Just (pMinK, pMinV)
      | otherwise -> Just (minK, minV)
    (Just mins, Nothing) -> Just mins
    (Nothing, Just mins) -> Just mins
    (Nothing, Nothing) -> Nothing
  where
    singleTransPeek (Transaction ref) (mbMins, deletedSet) = do
      TransactionData{..} <- readIORef ref
      let
        transMin = Map.lookupMin $ unModifyLog modifyLog
        updDeleted = maybe deletedSet (flip Set.insert deletedSet . fst)
          $ Set.minView (coerce deleteLog)
      pure $ case (mbMins, transMin) of
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
  :: Maybe (Transaction v)
  -> MvccMap Combined v
  -> IO (Maybe v)
peekIfExist = (fmap (fmap snd) .) . peekIfExistWithKey

pullIfExist
  :: Transaction v
  -> MvccMap Combined v
  -> IO (Maybe v)
pullIfExist trans mvccMap@MvccMap{..} = do
  forkIO $ readChan $ queueExtention ^. #pullLock
  mRes <- peekIfExistWithKey (Just trans) mvccMap
  maybe (pure Nothing) (\(k, v) -> delete k trans >> pure (Just v)) mRes

peek
  :: Maybe (Transaction v)
  -> MvccMap Combined v
  -> IO v
peek trans mvccMap@MvccMap{..} = do
  readChan $ queueExtention ^. #pullLock
  elm <- peekIfExist trans mvccMap
  writeChan (queueExtention ^. #pullLock) ()
  pure $ elm ^?! _Just

pull
  :: Transaction v
  -> MvccMap Combined v
  -> IO v
pull trans mvccMap@MvccMap{..} = do
  readChan $ queueExtention ^. #pullLock
  elm <- pullIfExist trans mvccMap
  pure $ elm ^?! _Just
