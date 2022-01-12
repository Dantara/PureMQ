module PureMQ.Types where

import           Data.Text     (Text)
import           GHC.Exception
import           GHC.Generics

newtype TransactionID = TransactionID
  { unTrasactionID :: Int }
  deriving (Eq, Ord, Show, Generic)

data TransactionError
  = WrongTransStatusChange TransStatus TransStatus
  | WrongTransStatus TransStatus
  | TransactionWasCancelled Text
  | TransactionWasNotFound TransactionID
  deriving (Eq, Ord, Show, Generic)

instance Exception TransactionError

data TransStatus
  = Initiated
  | Prepared
  | Committed
  | Canceled
  deriving (Eq, Ord, Show, Generic)

data IsolationLevel
  = ReadCommited
  | Serializable
  deriving (Eq, Ord, Show, Generic)
