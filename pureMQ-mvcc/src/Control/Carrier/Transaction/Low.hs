{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE UndecidableInstances #-}

module Control.Carrier.Transaction.Low where

import           Control.Algebra
import           Control.Effect.Lift
import           Control.Effect.Reader
import           Control.Effect.Transaction.Low hiding (commitPrepare)
import           Control.Monad.Catch
import           PureMQ.MVCC.Transaction
import           PureMQ.MVCC.Types              hiding (Transaction (..))
import           PureMQ.Types

newtype KeyValueSyncTransactionC m a = KeyValueSyncTransactionC
  { runKeyValueSyncTransaction :: m a }
  deriving (Applicative, Functor, Monad, MonadThrow, MonadCatch)

instance
  ( Has (Lift IO) sig m
  , Has (Reader (KeyValueMap v)) sig m
  , Monad m
  , Algebra sig m )
  => Algebra (Transaction :+: sig) (KeyValueSyncTransactionC m) where
  alg hdl sig ctx = KeyValueSyncTransactionC handled
    where
      handled = case sig of
        L (InitPrepare l)     -> fmap (<$ ctx) $ withMap $ sendIO . initPrepareKeyValue l
        L (CommitPrepare id') -> fmap (<$ ctx) $ withMap $ sendIO . commitPrepare id'
        L (Commit id')        -> fmap (<$ ctx) $ withMap $ sendIO . commitKeyValue id'
        L (Rollback id')      -> fmap (<$ ctx) $ withMap $ sendIO . cancelPrepare id'
        R other               -> alg (runKeyValueSyncTransaction . hdl) other ctx
        where
          withMap :: (KeyValueMap v -> m a) -> m a
          withMap = (ask @(KeyValueMap v) >>=)

newtype KeyValueAsyncTransactionC m a = KeyValueAsyncTransactionC
  { runKeyValueAsyncTransaction :: m a }
  deriving (Applicative, Functor, Monad, MonadThrow, MonadCatch)

instance
  ( Has (Lift IO) sig m
  , Has (Reader (KeyValueMap v)) sig m
  , Monad m
  , Algebra sig m )
  => Algebra (Transaction :+: sig) (KeyValueAsyncTransactionC m) where
  alg hdl sig ctx = KeyValueAsyncTransactionC handled
    where
      handled = case sig of
        L (InitPrepare l)     -> fmap (<$ ctx) $ withMap $ sendIO . initPrepareKeyValue l
        L (CommitPrepare id') -> fmap (<$ ctx) $ withMap $ sendIO . commitPrepare id'
        L (Commit id')        -> fmap (<$ ctx) $ withMap $ sendIO . commitAsyncKeyValue id'
        L (Rollback id')      -> fmap (<$ ctx) $ withMap $ sendIO . cancelPrepare id'
        R other               -> alg (runKeyValueAsyncTransaction . hdl) other ctx
        where
          withMap :: (KeyValueMap v -> m a) -> m a
          withMap = (ask @(KeyValueMap v) >>=)

newtype CombinedSyncTransactionC m a = CombinedSyncTransactionC
  { runCombinedSyncTransaction :: m a }
  deriving (Applicative, Functor, Monad, MonadThrow, MonadCatch)

instance
  ( Has (Lift IO) sig m
  , Has (Reader (CombinedMap v)) sig m
  , Monad m
  , Algebra sig m )
  => Algebra (Transaction :+: sig) (CombinedSyncTransactionC m) where
  alg hdl sig ctx = CombinedSyncTransactionC handled
    where
      handled = case sig of
        L (InitPrepare l)     -> fmap (<$ ctx) $ withMap $ sendIO . initPrepareCombined l
        L (CommitPrepare id') -> fmap (<$ ctx) $ withMap $ sendIO . commitPrepare id'
        L (Commit id')        -> fmap (<$ ctx) $ withMap $ sendIO . commitCombined id'
        L (Rollback id')      -> fmap (<$ ctx) $ withMap $ sendIO . cancelPrepare id'
        R other               -> alg (runCombinedSyncTransaction . hdl) other ctx
        where
          withMap :: (CombinedMap v -> m a) -> m a
          withMap = (ask @(CombinedMap v) >>=)

newtype CombinedAsyncTransactionC m a = CombinedAsyncTransactionC
  { runCombinedAsyncTransaction :: m a }
  deriving (Applicative, Functor, Monad, MonadThrow, MonadCatch)

instance
  ( Has (Lift IO) sig m
  , Has (Reader (CombinedMap v)) sig m
  , Monad m
  , Algebra sig m )
  => Algebra (Transaction :+: sig) (CombinedAsyncTransactionC m) where
  alg hdl sig ctx = CombinedAsyncTransactionC handled
    where
      handled = case sig of
        L (InitPrepare l)     -> fmap (<$ ctx) $ withMap $ sendIO . initPrepareCombined l
        L (CommitPrepare id') -> fmap (<$ ctx) $ withMap $ sendIO . commitPrepare id'
        L (Commit id')        -> fmap (<$ ctx) $ withMap $ sendIO . commitAsyncCombined id'
        L (Rollback id')      -> fmap (<$ ctx) $ withMap $ sendIO . cancelPrepare id'
        R other               -> alg (runCombinedAsyncTransaction . hdl) other ctx
        where
          withMap :: (CombinedMap v -> m a) -> m a
          withMap = (ask @(CombinedMap v) >>=)