{-# LANGUAGE AllowAmbiguousTypes  #-}
{-# LANGUAGE UndecidableInstances #-}

module Control.Carrier.Transaction where

import           Control.Algebra                    hiding (Handler)
import           Control.Carrier.Transaction.Cancel
import           Control.Effect.Exception
import           Control.Effect.Lift
import           Control.Effect.Reader
import           Control.Effect.Transaction
import qualified Control.Effect.Transaction.Low     as Low
import           Control.Monad.Catch                (MonadCatch, MonadThrow)
import           Lens.Micro
import           PureMQ.Database
import           PureMQ.GlobalTransactions
import           PureMQ.Types

newtype TransactionC m a = TransactionC
  { runTransactionC :: m a }
  deriving (Applicative, Functor, Monad, MonadThrow, MonadCatch)

instance
  ( Has (Lift IO) sig m
  , Has (Reader (Maybe TransactionID)) sig m
  , Has (Reader GTransactions) sig m
  , Algebra sig m )
  => Algebra (Transaction :+: sig) (TransactionC m) where
  alg hdl sig ctx = TransactionC handled
    where
      handled = case sig of
        L (Prepare actions) -> do
          gTranses <- ask
          tId <- sendIO $ initGTransaction gTranses
          resp <- try $ handle (gTransHandler gTranses tId) $ do
            result <- local (const $ Just tId)
              $ runTransactionC
              $ hdl . (<$ ctx)
              $ runPrepareT actions
            sendIO $ commitAllPrepare gTranses tId
            pure result
          pure $ case resp of
            Left err     -> Left err <$ ctx
            Right result -> fmap (Right . PreparedTransaction tId) result
        L (Commit prepared) -> fmap (<$ ctx) do
          gTranses <- ask
          let tId = prepared ^. #transactionId
          try $ handle (gTransHandler gTranses tId) do
            sendIO $ commitAll gTranses tId
            pure $ prepared ^. #result
        L (Rollback prepared) -> fmap (<$ ctx) do
          gTranses <- ask
          let tId = prepared ^. #transactionId
          flip catches [gRollbackHandler tId, rollbackHandler tId] do
            sendIO $ rollbackAll gTranses tId
            pure Nothing
        R other -> alg (runTransactionC . hdl) other ctx
        where
          gTransHandler :: GTransactions -> TransactionID -> GTransactionError -> m a
          gTransHandler gTranses tId _ = do
            sendIO $ rollbackAll gTranses tId
            throwIO $ TransactionWasNotFound tId
          gRollbackHandler :: TransactionID -> Handler m (Maybe TransactionError)
          gRollbackHandler tId
            = Handler
            $ \(_ :: GTransactionError) -> pure
            $ Just $ TransactionWasNotFound tId
          rollbackHandler :: TransactionID -> Handler m (Maybe TransactionError)
          rollbackHandler tId
            = Handler
            $ \(e :: TransactionError) -> pure $ Just e
