{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE UndecidableInstances #-}

module Control.Carrier.Transaction.Cancel where

import           Control.Algebra
import           Control.Effect.Exception
import           Control.Effect.Lift
import           Control.Effect.Transaction.Cancel
import           Control.Monad.Catch               (MonadCatch, MonadThrow)
import           PureMQ.Types

newtype CancelTransactionC m a = CancelTransactionC
  { runCancelTransactionC :: m a }
  deriving (Applicative, Functor, Monad, MonadThrow, MonadCatch)

instance
  Has (Lift IO) sig m
  => Algebra (CancelTransaction :+: sig) (CancelTransactionC m) where
  alg hdl sig ctx = CancelTransactionC handled
    where
      handled = case sig of
        L (Cancel msg) -> fmap (<$ ctx) $ throwIO $ TransactionWasCancelled msg
        R other        -> alg (runCancelTransactionC . hdl) other ctx
