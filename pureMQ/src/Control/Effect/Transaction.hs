{-# LANGUAGE AllowAmbiguousTypes      #-}
{-# LANGUAGE StandaloneKindSignatures #-}

module Control.Effect.Transaction where

import           Control.Algebra
import           Control.Effect.Transaction.Cancel
import qualified Control.Effect.Transaction.Low    as Low
import           Data.Kind
import           Data.Text                         (Text)
import           PureMQ.Types

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
    -> Transaction m (Either TransactionError (PreparedTransaction a))

  Commit
    :: PreparedTransaction a
    -> Transaction m (Either TransactionError a)

  Rollback
    :: PreparedTransaction a
    -> Transaction m (Maybe TransactionError)

prepare
  :: forall effs a t m sig
  .  ( Has CancelTransaction sig t
     , Has Transaction sig m
     , Storages effs sig m
     , Storages effs sig t
     , Has Low.Transaction sig m )
  => t a -> m (Either TransactionError (PreparedTransaction a))
prepare = send . Prepare @_ @_ @effs

commit
  :: Has Transaction sig m
  => PreparedTransaction a
  -> m (Either TransactionError a)
commit = send . Commit

rollback
  :: Has Transaction sig m
  => PreparedTransaction a
  -> m (Maybe TransactionError)
rollback = send . Rollback
