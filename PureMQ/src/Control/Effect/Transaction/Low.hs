{-# LANGUAGE AllowAmbiguousTypes #-}

module Control.Effect.Transaction.Low where

import           Control.Algebra
import           Data.Kind
import           Data.Text       (Text)
import           GHC.Generics
import           PureMQ.Types

data Transaction (m :: Type -> Type) r where
  InitPrepare :: Transaction m (Either TransactionError TransactionID)

  CommitPrepare
    :: TransactionID
    -> Transaction m (Maybe TransactionError)

  Commit
    :: TransactionID
    -> Transaction m (Maybe TransactionError)

  Rollback
    :: TransactionID
    -> Transaction m (Maybe TransactionError)

initPrepare
  :: forall m sig
  .  Has Transaction sig m
  => m (Either TransactionError TransactionID)
initPrepare = send InitPrepare

commitPrepare
  :: forall m sig
  .  Has Transaction sig m
  => TransactionID
  -> m (Maybe TransactionError)
commitPrepare = send . CommitPrepare

commit
  :: forall m sig
  .  Has Transaction sig m
  => TransactionID
  -> m (Maybe TransactionError)
commit = send . Commit

rollback
  :: forall m sig
  .  Has Transaction sig m
  => TransactionID
  -> m (Maybe TransactionError)
rollback = send . Rollback
