{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE UndecidableInstances #-}

module Control.Carrier.Storage.Single.KeyValue where

import           Control.Algebra
import           Control.Effect.Lift
import           Control.Effect.Reader
import           Control.Effect.Storage.Single.KeyValue
import           Control.Effect.Transaction.Low
import           Control.Monad.Catch
import           PureMQ.MVCC.KeyValue                   as I
import           PureMQ.MVCC.Types                      hiding
                                                        (Transaction (..))
import           PureMQ.Types

newtype KeyValueSingleStorageC (v :: *) m a = KeyValueSingleStorageC
  { runKeyValueSingleStorageC :: m a }
  deriving (Applicative, Functor, Monad, MonadThrow, MonadCatch)

instance
  ( Has (Lift IO) sig m
  , Has (Reader (MvccMap mode v)) sig m
  , Has (Reader (Maybe TransactionID)) sig m
  , Has Transaction sig m
  , Algebra sig m )
  => Algebra (KeyValueStorage Key v :+: sig) (KeyValueSingleStorageC v m) where
  alg hdl sig ctx = KeyValueSingleStorageC handled
    where
      handled = case sig of
        L (Lookup k) -> fmap (<$ ctx) $ withTransaction $ \tId -> do
          mvccMap <- ask @(MvccMap mode v)
          sendIO $ I.lookup k tId mvccMap
        L (Insert k v) -> fmap (<$ ctx) $ withTransaction $ \tId -> do
          mvccMap <- ask @(MvccMap mode v)
          sendIO $ I.insert k v tId mvccMap
        L (Modify k f) -> fmap (<$ ctx) $ withTransaction $ \tId -> do
          mvccMap <- ask @(MvccMap mode v)
          sendIO $ I.modify k f tId mvccMap
        L (Delete k) -> fmap (<$ ctx) $ withTransaction $ \tId -> do
          mvccMap <- ask @(MvccMap mode v)
          sendIO $ I.delete k tId mvccMap
        R other      -> alg (runKeyValueSingleStorageC . hdl) other ctx
        where
          withTransaction action = ask >>= \case
            Just tId ->
              action tId
            Nothing -> do
              tId <- initPrepare ReadCommitted
              r <- action tId
              commitPrepare tId
              commit tId
              pure r
