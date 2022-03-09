{-# LANGUAGE UndecidableInstances #-}

module Control.Carrier.DBControl where

import           Control.Algebra
import           Control.Carrier.Storage.Single.KeyValue
import           Control.Carrier.Storage.Single.Queue
import           Control.Carrier.Transaction.Low         as L
import           Control.Effect.DBControl
import           Control.Effect.Lift
import           Control.Effect.Reader
import           Control.Effect.Storage.KeyValue
import           Control.Effect.Storage.Queue
import qualified Control.Effect.Storage.Single.KeyValue  as S
import qualified Control.Effect.Storage.Single.Queue     as S
import           Control.Effect.Transaction.Low          as L
import           Control.Monad.Catch
import           Control.Monad.Trans.Reader              (ReaderT, runReaderT)
import           Data.Coerce
import           Data.Kind
import qualified Data.Map.Strict                         as Map
import qualified Data.Set                                as Set
import           GHC.MVar
import           Lens.Micro
import           PureMQ.Database                         as DB
import           PureMQ.MVCC.Init
import           PureMQ.MVCC.Types
import           PureMQ.Types

newtype CombinedSyncDatabaseC m a = CombinedSyncDatabaseC
  { runCombinedSyncDatabaseC :: m a }
  deriving (Applicative, Functor, Monad, MonadThrow, MonadCatch)

type KeyValueC v a
  = KeyValueSingleStorageC CombinedM v
  ( CombinedSyncTransactionC v
    ( ReaderT (CombinedMap v)
      ( ReaderT (Maybe TransactionID) IO )
    )
  ) a

type QueueC v a
  = QueueSingleStorageC v
  ( CombinedSyncTransactionC v
    ( ReaderT (CombinedMap v)
      ( ReaderT (Maybe TransactionID) IO )
    )
  ) a

type TransC v a = CombinedSyncTransactionC v (ReaderT (CombinedMap v) IO) a

instance
  ( Has (Reader DBCounter) sig m
  , Has (Lift IO) sig m )
  => Algebra (DBControl :+: sig) (CombinedSyncDatabaseC m) where
  alg hdl sig ctx = CombinedSyncDatabaseC case sig of
    L InitDB -> fmap (<$ ctx)
      $ ask >>= nextDatabaseId >>= newDatabase
    L (AddStorage (name :: StorageName k v) types db) -> fmap (<$ ctx) do
      storages <- sendIO $ takeMVar $ db ^. #storages
      mvccMap <- sendIO $ initCombinedMap @v $ Just 1000 -- FIXME Move delay to Reader
      let
        keyValCarrier
          | Set.member KeyValue types
            = Just
            $ StorageCarrier @(S.KeyValueStorage Key v)
            $ \mtId (ma :: KeyValueC v a) ->
            flip runReaderT mtId
            $ flip runReaderT mvccMap
            $ runCombinedSyncTransactionC
            $ runKeyValueSingleStorageC ma
          | otherwise = Nothing
        queueCarrier
          | Set.member Queue types
            = Just
            $ StorageCarrier @(S.QueueStorage v)
            $ \mtId (ma :: QueueC v a) ->
            flip runReaderT mtId
            $ flip runReaderT mvccMap
            $ runCombinedSyncTransactionC
            $ runQueueSingleStorageC ma
          | otherwise = Nothing
        transCarrier
          = TransactionCarrier
          $ \(ma :: TransC v a) ->
          flip runReaderT mvccMap
          $ runCombinedSyncTransactionC ma
        newStorage = Storage $ Carriers{..}
      sendIO
        $ putMVar (db ^. #storages)
        $ coerce
        $ Map.insert (coerce name) newStorage (coerce storages)
    L (RemoveStorage name db) -> (<$ ctx) <$> DB.removeStorage name db
    R other  -> alg (runCombinedSyncDatabaseC . hdl) other ctx
