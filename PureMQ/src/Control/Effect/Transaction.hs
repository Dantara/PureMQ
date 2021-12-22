{-# LANGUAGE AllowAmbiguousTypes      #-}
{-# LANGUAGE StandaloneKindSignatures #-}

module Control.Effect.Transaction where

import           Control.Algebra
import           Control.Effect.Storage.Common
import           Control.Effect.Transaction.Low (TransactionError (..),
                                                 TransactionID (..))
import           Data.Kind
import           Data.Text                      (Text)

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

data Transaction a (m :: Type -> Type) r where
  Prepare
    :: forall effs a m t sig
    . ( Has CancelTransaction sig t
      , Storages effs sig m )
    => t a
    -> Transaction a m (Either TransactionError TransactionID)

  Commit
    :: TransactionID
    -> Transaction a m (Either TransactionError a)

  Rollback
    :: TransactionID
    -> Transaction a m (Maybe TransactionError)
