{-# LANGUAGE AllowAmbiguousTypes #-}

module Control.Effect.Transaction.Low where

import           Control.Algebra
import           Data.Kind
import           Data.Text       (Text)
import           GHC.Generics

newtype TransactionID = TransactionID
  { unTrasactionID :: Int }
  deriving (Eq, Ord, Show, Generic)

data TransactionError
  = SomeTransactionError
  | TransactionWasCancelled Text
  deriving (Eq, Ord, Show, Generic)

data TransStatus
  = Initiated
  | Prepared
  | Commited
  | Canceled
  deriving (Eq, Ord, Show, Generic)

data Transaction a (m :: Type -> Type) r where
  InitPrepare :: Transaction a m (Either TransactionError TransactionID)

  CommitPrepare
    :: TransactionID
    -> Transaction a m (Maybe TransactionError)

  Commit
    :: TransactionID
    -> Transaction a m (Either TransactionError a)

  Rollback
    :: TransactionID
    -> Transaction a m (Maybe TransactionError)

initPrepare
  :: forall a m sig
  .  Has (Transaction a) sig m
  => m (Either TransactionError TransactionID)
initPrepare = send $ InitPrepare @a

commitPrepare
  :: forall a m sig
  .  Has (Transaction a) sig m
  => TransactionID
  -> m (Maybe TransactionError)
commitPrepare = send . CommitPrepare @a

commit
  :: forall a m sig
  .  Has (Transaction a) sig m
  => TransactionID
  -> m (Either TransactionError a)
commit = send . Commit @a

rollback
  :: forall a m sig
  .  Has (Transaction a) sig m
  => TransactionID
  -> m (Maybe TransactionError)
rollback = send . Rollback @a
