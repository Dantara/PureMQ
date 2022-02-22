{-# LANGUAGE AllowAmbiguousTypes      #-}
{-# LANGUAGE StandaloneKindSignatures #-}
{-# LANGUAGE UndecidableInstances     #-}

module Control.Effect.Transaction where

import           Control.Algebra
import           Control.Effect.Transaction.Cancel
import qualified Control.Effect.Transaction.Low    as Low
import           Control.Monad.Catch
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
  Storages (x ': xs) sig m = (Has x sig m, StorageEff x, Storages xs sig m)

newtype PrepareT sig m a = PrepareT { runPrepareT :: m a }
  deriving (Functor, Applicative, Monad, MonadThrow, MonadCatch)

instance
  ( Algebra sig m
  , Storages xs sig m
  , Has CancelTransaction sig m )
  => Algebra sig (PrepareT sig m) where
  alg hdl sig ctx = PrepareT $ alg (runPrepareT . hdl) sig ctx

data Transaction (m :: Type -> Type) r where
  Prepare
    :: ( Has CancelTransaction sig m
       , Storages effs sig m )
    => PrepareT sig m a
    -> Transaction m (Either TransactionError (PreparedTransaction a))

  Commit
    :: PreparedTransaction a
    -> Transaction m (Either TransactionError a)

  Rollback
    :: PreparedTransaction a
    -> Transaction m (Maybe TransactionError)

prepare'
  :: forall effs a m sig
  .  ( Has CancelTransaction sig m
     , Has Transaction sig m
     , Storages effs sig m )
  => PrepareT sig m a
  -> m (Either TransactionError (PreparedTransaction a))
prepare' = send . Prepare @_ @_ @effs

prepare
  :: forall effs a m sig
  .  ( Has CancelTransaction sig m
     , Has Transaction sig m
     , Storages effs sig m )
  => m a -> m (Either TransactionError (PreparedTransaction a))
prepare = prepare' @effs . PrepareT

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
