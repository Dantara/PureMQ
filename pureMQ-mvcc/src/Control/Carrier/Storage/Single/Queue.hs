{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE UndecidableInstances #-}

module Control.Carrier.Storage.Single.Queue where

import           Control.Algebra
import           Control.Effect.Lift
import           Control.Effect.Reader
import           Control.Effect.Storage.Single.Queue
import           Control.Effect.Transaction.Low
import           Control.Monad.Catch
import           PureMQ.MVCC.Queue                   as I
import           PureMQ.MVCC.Types                   hiding (Transaction (..))
import           PureMQ.Types

newtype QueueSingleStorageC v m a = QueueSingleStorageC
  { runQueueSingleStorage :: m a }
  deriving (Applicative, Functor, Monad, MonadThrow, MonadCatch)

instance
  ( Has (Lift IO) sig m
  , Has (Reader (CombinedMap v)) sig m
  , Has (Reader (Maybe TransactionID)) sig m
  , Has Transaction sig m
  , Monad m
  , Algebra sig m )
  => Algebra (QueueStorage v :+: sig) (QueueSingleStorageC v m) where
  alg hdl sig ctx = QueueSingleStorageC handled
    where
      handled = case sig of
        L (Push v) -> fmap (<$ ctx) $ withTransaction $ \tId -> do
          mvccMap <- ask @(CombinedMap v)
          sendIO $ I.push v tId mvccMap
        L Pull -> fmap (<$ ctx) $ withTransaction $ \tId -> do
          mvccMap <- ask @(CombinedMap v)
          sendIO $ I.pull tId mvccMap
        L PullIfExist -> fmap (<$ ctx) $ withTransaction $ \tId -> do
          mvccMap <- ask @(CombinedMap v)
          sendIO $ I.pullIfExist tId mvccMap
        L Peek -> fmap (<$ ctx) $ withTransaction $ \tId -> do
          mvccMap <- ask @(CombinedMap v)
          sendIO $ I.peek tId mvccMap
        L PeekIfExist -> fmap (<$ ctx) $ withTransaction $ \tId -> do
          mvccMap <- ask @(CombinedMap v)
          sendIO $ I.peekIfExist tId mvccMap
        R other      -> alg (runQueueSingleStorage . hdl) other ctx
        where
          withTransaction action = ask >>= \mId ->
            case mId of
              Just tId ->
                action tId
              Nothing -> do
                tId <- initPrepare ReadCommited
                r <- action tId
                commitPrepare tId
                commit tId
                pure r
