module PureMQ.MVCC.Init where

import           Control.Concurrent
import           Control.Concurrent.MVar      (readMVar)
import           Control.Concurrent.STM.TChan
import           Control.Concurrent.STM.TVar
import           Control.Monad
import           Data.Coerce
import           Data.Generics.Labels         ()
import           Data.IntMap                  (IntMap)
import qualified Data.IntMap                  as Map
import           Data.IntSet                  (IntSet)
import qualified Data.IntSet                  as Set
import           GHC.Generics
import           GHC.IORef
import           Lens.Micro
import           PureMQ.MVCC.Transaction
import           PureMQ.MVCC.Types
import           PureMQ.Types

runAutoVacuum :: Int -> MvccMap m v -> IO ThreadId
runAutoVacuum delay mvccMap = forkIO $ forever do
  vacuum mvccMap
  threadDelay delay

initKeyValueMap :: Maybe Int -> IO (KeyValueMap v)
initKeyValueMap mDelay = do
  primaryMap <- newIORef $! Map.empty
  uncommitted <- newTVarIO $! UncommittedTransactions 0 Map.empty
  committed <- newTVarIO $! CommittedTransactions Nothing Map.empty
  let
    queueExtention = ()
    mvccMap = MvccMap{..}
  maybe (pure ()) (void . flip runAutoVacuum mvccMap) mDelay
  pure mvccMap

runIncrementer :: Key -> MVar Key -> IO ()
runIncrementer i var = void $ forkIO do
  putMVar var $! i
  runIncrementer (i + 1) var

initCombinedMap :: Maybe Int -> IO (CombinedMap v)
initCombinedMap mDelay = do
  primaryMap <- newIORef $! Map.empty
  uncommitted <- newTVarIO $! UncommittedTransactions 0 Map.empty
  committed <- newTVarIO $! CommittedTransactions Nothing Map.empty
  nextKey <- newEmptyMVar
  pullLock <- newTChanIO
  let
    queueExtention = QueueExtention{..}
    mvccMap = MvccMap{..}
  runIncrementer 0 nextKey
  maybe (pure ()) (void . flip runAutoVacuum mvccMap) mDelay
  pure mvccMap
