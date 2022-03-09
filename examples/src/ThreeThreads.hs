{-# LANGUAGE OverloadedLists #-}

module ThreeThreads where

import           Control.Algebra
import           Control.Carrier.DBControl          (runCombinedSyncDatabaseC)
import           Control.Carrier.Storage.Queue
import           Control.Carrier.Transaction
import           Control.Carrier.Transaction.Cancel
import           Control.Concurrent.Async
import           Control.Effect.DBControl
import           Control.Effect.Exception
import           Control.Effect.Lift
import           Control.Effect.Storage
import           Control.Effect.Storage.Queue
import           Control.Effect.Transaction
import           Control.Effect.Transaction.Cancel
import           Control.Monad.Trans.Reader         (ReaderT, runReaderT)
import           Data.Function
import           PureMQ.Database                    hiding (addStorage)
import           PureMQ.GlobalTransactions          hiding (commit)
import           PureMQ.MVCC.Types                  hiding (Transaction (..))
import           PureMQ.Types

storageName :: StorageName Key Int
storageName = "some_storage"

runThreeThreads :: IO ()
runThreeThreads = do
  (db1, db2) <- initDBs
  gTranses <- sendIO initGTransactions
  async1 <- sendIO
    $ async
    $ flip runReaderT (Nothing @TransactionID)
    $ flip runReaderT gTranses
    $ runQueueStorageC
    $ processReader db1
  async2 <- sendIO
    $ async
    $ flip runReaderT (Nothing @TransactionID)
    $ flip runReaderT gTranses
    $ runQueueStorageC
    $ runCancelTransactionC
    $ runTransactionC
    $ processCalculator db1 db2
  async3 <- sendIO
    $ async
    $ flip runReaderT (Nothing @TransactionID)
    $ flip runReaderT gTranses
    $ runQueueStorageC
    $ processPrinter db2
  sendIO $ wait async1
  sendIO $ wait async2
  sendIO $ wait async3

initDBs :: Has (Lift IO) sig m => m (Database, Database)
initDBs = do
  dbCounter <- initDBCounter
  flip runReaderT dbCounter $ runCombinedSyncDatabaseC do
    db1 <- initDB
    db2 <- initDB
    addStorage storageName [Queue, KeyValue] db1
    addStorage storageName [Queue, KeyValue] db2
    pure (db1, db2)

processReader
  :: ( Has (Lift IO) sig m
     , Has QueueStorage sig m )
  => Database
  -> m ()
processReader db = fix $ \repeat -> do
  nextInt <- (read @Int) <$> sendIO getLine
  push db storageName nextInt
  repeat

processCalculator
  :: ( Has (Lift IO) sig m
     , Has QueueStorage sig m
     , Has CancelTransaction sig m -- FIXME Should not leak
     , Has Transaction sig m )
  => Database
  -> Database
  -> m ()
processCalculator dbFrom dbTo = fix $ \repeat -> do
  eResult <- unsafePrepare @'[QueueStorage] do -- FIXME use safe prepare
    received <- pull dbFrom storageName
    push dbTo storageName (received + 1)
  result <- either throwIO pure eResult
  either throwIO pure =<< commit result
  repeat

processPrinter
  :: ( Has (Lift IO) sig m
     , Has QueueStorage sig m )
  => Database
  -> m ()
processPrinter db = fix $ \repeat -> do
  nextInt <- pull db storageName
  sendIO $ print nextInt
  repeat
