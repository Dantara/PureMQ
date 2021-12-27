module PureMQ.MVCC.KeyValue where

import           Control.Concurrent
import           Control.Concurrent.MVar (readMVar)
import           Control.Exception
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

data WasDeleted = WasDeleted
  deriving (Eq,Show, Generic)

instance Exception WasDeleted

lookup :: Key -> Maybe (Transaction v) -> MvccMap m v -> IO (Maybe v)
lookup k mTrans MvccMap{..} = do
  committed <- readMVar transactionsQueue
  let transactions = maybe committed (committed |>) mTrans
  tsLookupResult <- transLookup transactions
  case tsLookupResult of
    Nothing -> do
      pMap <- readIORef primaryMap
      pure $ Map.lookup (coerce k) pMap
    Just v ->
      pure $ Just v
  where
    transLookup ts = case Seq.viewr ts of
      EmptyR -> pure Nothing
      others :> curr -> do
        mVal <- singleTransLookup curr
        maybe (transLookup others) (pure . Just) mVal
    singleTransLookup (Transaction ref) = do
      TransactionData{..} <- readIORef ref
      when (Set.member (coerce k) (coerce deleteLog))
        $ throwIO WasDeleted
      pure $ Map.lookup (coerce k) (unModifyLog modifyLog)

insert :: Key -> v -> Transaction v -> IO (Maybe TransactionError)
insert k v (Transaction ref) = do
  td@TransactionData{..} <- readIORef ref
  case status of
    Initiated -> do
      let updated = coerce $ Map.insert (coerce k) v (coerce modifyLog)
      writeIORef ref $! set #modifyLog updated td
      pure Nothing
    status ->
      pure $ Just $ WrongTransStatus status

modify :: Key -> (v -> v) -> Transaction v -> IO (Maybe TransactionError)
modify k f (Transaction ref) = do
  td@TransactionData{..} <- readIORef ref
  case status of
    Initiated -> do
      let updated = coerce $ Map.adjust f (coerce k) (coerce modifyLog)
      writeIORef ref $! set #modifyLog updated td
      pure Nothing
    status ->
      pure $ Just $ WrongTransStatus status

delete :: forall v. Key -> Transaction v -> IO (Maybe TransactionError)
delete k (Transaction ref) = do
  td@TransactionData{..} <- readIORef ref
  case status of
    Initiated -> do
      let
        deleteLog = coerce $ Set.insert (coerce k) (coerce deleteLog)
        modifyLog = coerce $ Map.delete (coerce k) (unModifyLog modifyLog)
      writeIORef ref $! set #deleteLog deleteLog td
      writeIORef ref $! set #modifyLog modifyLog td
      pure Nothing
    status ->
      pure $ Just $ WrongTransStatus status
