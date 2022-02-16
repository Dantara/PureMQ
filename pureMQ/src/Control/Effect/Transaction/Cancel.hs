module Control.Effect.Transaction.Cancel where

import           Control.Algebra
import           Data.Kind
import           Data.Text       (Text)

data CancelTransaction (m :: Type -> Type) r where
  Cancel :: Text -> CancelTransaction m ()

cancel
  :: Has CancelTransaction sig m
  => Text -> m ()
cancel = send . Cancel
