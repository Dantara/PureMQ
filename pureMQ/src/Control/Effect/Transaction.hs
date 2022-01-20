{-# LANGUAGE AllowAmbiguousTypes      #-}
{-# LANGUAGE StandaloneKindSignatures #-}

module Control.Effect.Transaction where

import           Control.Algebra
import qualified Control.Effect.Transaction.Low as Low
import           Data.Kind
import           Data.Text                      (Text)
import           PureMQ.Types

data CancelTransaction (m :: Type -> Type) r where
  Cancel :: Text -> CancelTransaction m ()

cancel
  :: Has CancelTransaction sig m
  => Text -> m ()
cancel = send . Cancel

type Storages
  :: [(Type -> Type) -> Type -> Type]
  -> ((Type -> Type) -> Type -> Type)
  -> (Type -> Type)
  -> Constraint

type family Storages xs sig m where
  Storages '[] sig m = ()
  Storages (x ': xs) sig m = (Has x sig m, StorageEff x)

data Transaction (m :: Type -> Type) r where
  Prepare
    :: ( Has CancelTransaction sig t
      , Storages effs sig m
      , Storages effs sig t )
    => t a
    -> Transaction m (Either TransactionError TransactionID)

  Commit
    :: TransactionID
    -> Transaction m (Maybe TransactionError)

  Rollback
    :: TransactionID
    -> Transaction m (Maybe TransactionError)

  -- Later, we want to have the following interface for commit:
  -- >>> Commit
  -- >>>  :: TransactionID
  -- >>>  -> Transaction effs a m (Either TransactionError a)


prepare
  :: forall effs a t m sig
  .  ( Has CancelTransaction sig t
     , Has Transaction sig m
     , Storages effs sig m
     , Storages effs sig t
     , Has Low.Transaction sig m )
  => t a -> m (Either TransactionError TransactionID)
prepare = send . Prepare @_ @_ @effs

commit
  :: Has Transaction sig m
  => TransactionID
  -> m (Maybe TransactionError)
commit = send . Commit

rollback
  :: Has Transaction sig m
  => TransactionID
  -> m (Maybe TransactionError)
rollback = send . Rollback
