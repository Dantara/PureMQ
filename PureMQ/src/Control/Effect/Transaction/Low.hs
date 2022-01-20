{-# LANGUAGE AllowAmbiguousTypes #-}

module Control.Effect.Transaction.Low where

import           Control.Algebra
import           Data.Kind
import           Data.Text       (Text)
import           GHC.Generics
import           PureMQ.Types

data Transaction (m :: Type -> Type) r where
  InitPrepare
    :: IsolationLevel
    -> Transaction m TransactionID

  CommitPrepare
    :: TransactionID
    -> Transaction m ()

  Commit
    :: TransactionID
    -> Transaction m ()

  Rollback
    :: TransactionID
    -> Transaction m ()

initPrepare
  :: forall m sig
  .  Has Transaction sig m
  => IsolationLevel
  -> m TransactionID
initPrepare = send . InitPrepare

commitPrepare
  :: forall m sig
  .  Has Transaction sig m
  => TransactionID
  -> m ()
commitPrepare = send . CommitPrepare

commit
  :: forall m sig
  .  Has Transaction sig m
  => TransactionID
  -> m ()
commit = send . Commit

rollback
  :: forall m sig
  .  Has Transaction sig m
  => TransactionID
  -> m ()
rollback = send . Rollback
